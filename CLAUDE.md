# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

StarTime is a SwiftUI iOS app for families to track kids' chores and reward them with points redeemable for prizes.

The backend is a serverless AWS stack living in `backend/` — **Cognito** (auth), **API Gateway + Lambda** (REST), **DynamoDB** (single-table), and an **API Gateway WebSocket API + DynamoDB Streams** (realtime), all provisioned with **AWS CDK in TypeScript**. The iOS client talks to it over HTTPS; it holds no AWS credentials and no direct database access.

It was originally built on Firebase (Auth + Firestore called directly from the client). That migration is finished and fully unwound: no code, dependency, or deployed resource references Firebase. The only trace left is `custom:legacy_uid` — the app-level user id that exists precisely *because* Cognito's `sub` is regenerated per user pool, which is what let existing households survive the provider change.

## Build & test

There's no Makefile/fastlane — use `xcodebuild` directly. The only scheme is `StarTime`.

**Every `xcodebuild` invocation needs `-skipPackagePluginValidation`.** `smithy-swift` (a transitive dependency of `aws-sdk-swift`) ships a code-generation build tool plugin, and Xcode's command-line plugin-trust prompt doesn't persist between invocations the way it does in the GUI — omit the flag and the build fails at "Validate plug-in “SmithyCodeGeneratorPlugin”" every time.

**The app needs backend endpoints injected at build time** (see "Configuration" below), so a bare `xcodebuild build` produces an app that can't reach a backend. That's fine for a compile check; use `with-ephemeral-stack.sh` (below) for anything that actually runs.

```bash
# Compile check only
xcodebuild build -project StarTime.xcodeproj -scheme StarTime \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

### Running tests

**UI tests are integration tests against a real, disposable AWS stack** — not mocks, not a local emulator. `backend/scripts/with-ephemeral-stack.sh` deploys a uniquely-named stack set, exports its outputs as `STARTIME_*` env vars, runs whatever command you give it, and **always tears the stack down on exit** (success or failure) via a shell trap:

```bash
# Full UI suite against a throwaway stack
./backend/scripts/with-ephemeral-stack.sh -- bash -c '
  xcodebuild test -project StarTime.xcodeproj -scheme StarTime \
    -destination "platform=iOS Simulator,id=<SIMULATOR_UDID>" \
    -only-testing:StarTimeUITests \
    -skipPackagePluginValidation -parallel-testing-enabled NO \
    STARTIME_USER_POOL_ID="$STARTIME_USER_POOL_ID" \
    STARTIME_USER_POOL_CLIENT_ID="$STARTIME_USER_POOL_CLIENT_ID" \
    STARTIME_AWS_REGION=us-west-2 \
    STARTIME_API_HOST="$STARTIME_API_HOST" \
    STARTIME_WS_HOST="$STARTIME_WS_HOST"'
```

Use a specific simulator **UDID**, not a name: a name-based destination lets Xcode clone simulators, and a cloned runner intermittently fails to launch.

Some behavior can't be tested through XCUITest at all, because the suite drives a single client. Those have dedicated Node scripts under `backend/cdk/scripts/`, run the same way (they read the `STARTIME_*` env vars):

- `verify-realtime.mjs` — opens a WebSocket, writes over REST, asserts the pushed invalidation arrives. Covers authorizer → `$connect` → Streams → fan-out.
- `verify-duplicate-guard.mjs` — fires 5 identical completions concurrently, asserts exactly one 201 and four 409s.
- `verify-migration-shape.mjs` — writes items straight into DynamoDB, bypassing every handler, then reads them back through the API. Catches what the UI tests can't: they only read back what the handlers themselves wrote, so a sort key outside a query's range or a missing GSI attribute would pass unnoticed. Relevant to anything that writes to the table out-of-band (backfill, repair, restore).

They live under `backend/cdk/` because ESM resolves imports relative to the file, and `node_modules` is there.

### Cost/latency note

Each ephemeral run deploys and destroys real AWS resources — typically ~1–3 minutes each way, longer under throttling. Prefer targeting a single test while iterating.

## Configuration

The app has no hardcoded endpoints. `StarTime/Config/StarTime.xcconfig` declares build settings that `SupportingFiles/Info.plist` interpolates, and `BackendConfig.swift` reads them (with a `ProcessInfo.environment` override for launch-time swapping).

**`Info.plist` lives in `SupportingFiles/`, deliberately outside `StarTime/`.** That folder is an Xcode 16 synchronized group, which auto-sweeps everything under it into Copy Bundle Resources — including the Info.plist, causing "Multiple commands produce Info.plist". Resource-phase membership exceptions do *not* reliably suppress this; relocating the file is the fix.

**A URL can't live in an xcconfig** — `//` starts a comment. Hence the split `STARTIME_API_SCHEME`/`STARTIME_API_HOST` pair, recombined in Info.plist.

## Architecture

Each feature area (household, chores, rewards) follows the same layering:

**Model → Service → Store → View**

- **Models** (`StarTime/Models/`): plain `Codable` structs mirroring the JSON the Lambdas return. Timestamps are ISO8601 **with fractional seconds** (`new Date().toISOString()`), which Swift's stock `.iso8601` strategy rejects — `APIClient` installs a custom decoding strategy for this.
- **Services** (`StarTime/Services/*Service.swift`): stateless structs wrapping `APIClient`. They own endpoint paths and map HTTP status codes to domain errors (404 → `HouseholdServiceError.invalidCode`, 409 → `RewardServiceError.insufficientBalance` / "already completed today"). Views never call these directly.
- **Stores** (`StarTime/Services/*Store.swift`): `@MainActor final class ... ObservableObject`. Hold `@Published` state, expose `start(householdId:)`/`stop()`/`refresh()`, and own derived view logic (`ChoreStore.streak(for:)`, `choresDueToday(for:)`, `RewardStore.balance(for:)`).
- **Views** (`StarTime/Views/`): SwiftUI, injected with stores via `.environmentObject`.

`APIClient` (`StarTime/Services/APIClient.swift`) is a `@MainActor` singleton: URLSession, bearer-token auth, typed decode, and a single 401-refresh-retry. Its `tokenProvider` is wired in `AuthService.init()` — **not** from the App body, because a `.task`-based assignment races the first request.

Composition root: `StarTimeApp.swift` (owns `AuthService`) → `ContentView.swift` (auth/onboarding gate) → `MainTabView.swift` (owns the **shared** `ChoreStore`, `RewardStore`, and `RealtimeConnectionManager`).

### Conventions that are load-bearing

- **Stores are shared, not per-view.** `ChoreStore`/`RewardStore` are `@StateObject`s on `MainTabView`, injected downward. They used to be per-view, which Firestore's snapshot listeners silently compensated for by pushing every write to every instance. With fetch-based stores, a write through one instance is invisible to the others — sharing is a correctness requirement now.
- **`observe(_:)` subscriptions must not be torn down by `stop()`.** `start()` calls `stop()` internally, so clearing the subscription there unsubscribes the store from all realtime pushes — a bug that made the entire realtime layer silently dead while the backend looked healthy. `refresh()` no-ops without a household, so a late invalidation is harmless.
- **Never refetch in response to a `@Published` change of a store the view observes.** `RewardsView.onAppear { refresh() }` fed back into `MainTabView`'s re-render, which re-fired `onAppear`; the app never went idle and XCUITest stalled for 900+ seconds per tap. Cross-store updates travel via realtime invalidation instead.
- **`ChoreService.dayString(_:)` is the canonical `scheduledDate` formatter.** Completions are matched by exact string equality on it (streaks, once-per-day). Never format that date ad hoc.
- **Background refetch failures are not user-facing.** Only user-initiated actions populate `errorMessage`; a transient failure raised as a modal alert blocks UI interaction (including XCUITest taps).

## Backend (`backend/`)

```
backend/cdk/
  bin/startime.ts          — app entry; every stack is suffixed by --context stage=
  lib/{health,auth,data,api,realtime}-stack.ts
  lib/constructs/rest-lambda.ts
  lambda/{auth,household,chores,rewards,realtime,common}/
  scripts/                 — verification + migration scripts (Node ESM)
backend/scripts/
  with-ephemeral-stack.sh  — deploy → run → always destroy
  deploy-prod.sh           — diff → confirm → deploy; no teardown path
```

**Stages.** Everything is namespaced by `--context stage=`. `prod` holds real family data; `test-<runid>` stages are created and destroyed per test run.

**CDK's default removal policy is RETAIN for stateful resources.** Both the DynamoDB table and the Cognito User Pool set `stage === 'prod' ? RETAIN : DESTROY` explicitly. Without that, every ephemeral test run silently orphans a User Pool. Apply the same treatment to any new stateful resource.

### DynamoDB single-table design

```
Household metadata   PK=HOUSEHOLD#{id}      SK=METADATA
User profile          PK=USER#{uid}          SK=PROFILE
Chore                  PK=HOUSEHOLD#{id}      SK=CHORE#{choreId}
Reward                 PK=HOUSEHOLD#{id}      SK=REWARD#{rewardId}
Completion              PK=HOUSEHOLD#{id}      SK=COMPLETION#{completedAtISO}#{id}
Redemption              PK=HOUSEHOLD#{id}      SK=REDEMPTION#{redeemedAtISO}#{id}
Balance                PK=HOUSEHOLD#{id}      SK=BALANCE#{uid}
Completion marker       PK=HOUSEHOLD#{id}      SK=COMPLETEDON#{choreId}#{scheduledDate}
Invite code             PK=INVITECODE#{code}   SK=METADATA   GSI1PK=HOUSEHOLD#{id}  GSI1SK=INVITECODE#{code}
```

- **Range queries need an explicit upper bound.** Completions/redemptions use `SK BETWEEN 'COMPLETION#{since}' AND 'COMPLETION#~'`. A bare `SK > :since` also matches `METADATA`/`REWARD#`/etc. under the same PK.
- **`COMPLETEDON#` sorts before `COMPLETION#`** (`'E' < 'I'`), so markers fall outside the completion range and never leak into results. They *are* invisible to `begins_with('COMPLETION#')` too — cascade delete names them explicitly.
- **GSI1 exists for one query**: finding a household's invite codes during cascade delete.

### Authorization

Firestore's console-only security rules are gone; **authorization now lives in version-controlled Lambda code**. Every handler derives the caller's identity from `custom:legacy_uid` in the authorizer-validated token claims (`common/auth.ts`) and re-derives their `householdId` server-side. **Never trust a client-supplied uid or householdId.**

**`custom:legacy_uid`, not Cognito's `sub`, is the canonical app-level user id.** Set by the `PostConfirmation` trigger at sign-up, for every account. The name is historical — `sub` is regenerated per user pool, so data keyed on it could never have survived the provider change; a separate stable id is what let existing households stay reachable.

**The App Client uses `USER_PASSWORD_AUTH`, not SRP, and that's load-bearing.** `AuthService.signIn` calls `InitiateAuth` with `.userPasswordAuth`, and aws-sdk-swift ships no SRP implementation (it's in Amplify, which this app doesn't use). Enabling SRP and disabling this breaks sign-in. It was originally chosen so the since-removed migration trigger could verify plaintext passwords against Firebase, but the client now depends on it independently.

### Realtime

DynamoDB Streams → fan-out Lambda → WebSocket push of a **lightweight invalidation** (`{"type":"invalidate","resources":["chores","balances"]}`), not the changed data. Clients refetch. This avoids merge/ordering logic entirely and matches how the stores already behave after their own writes.

- **WebSocket Lambda authorizers must return an IAM policy document.** The simple `{ isAuthorized: true }` shape is HTTP-API-only; returning it from a WebSocket authorizer fails the handshake with a bare 1006 close and no diagnostic.
- **The ID token rides in `?token=`**, because native WebSocket handshakes can't set headers. It would appear in API Gateway access logs if those were enabled.
- **iOS suspends backgrounded apps and kills the socket without the app observing the failure**, so it can't self-heal via the reconnect path. `MainTabView` refetches and reconnects on `scenePhase == .active`. A push sent to a sleeping device is simply lost — there's no queue.

### Invariants worth preserving

- **Balances are a denormalized counter**, updated in the same `TransactWriteItems` as the completion/redemption that justifies them. They must never drift from the ledger.
- **Redemption is atomic**: the balance decrement carries `ConditionExpression: balance >= :cost`, so the write itself enforces sufficiency. The old client-side pre-check could be beaten by two concurrent redemptions.
- **One completion per chore per day** is enforced by a conditional `Put` of the `COMPLETEDON#` marker in the same transaction. A completion's own sort key carries a timestamp and uuid and can never collide, so it can't be the constraint. `verify-duplicate-guard.mjs` proves this under concurrency.
- **Cascade delete ordering**: `DELETE /account` removes completions, markers, redemptions, chores, rewards, balances, invite codes (via GSI1), then the household — household last, so a partial failure leaves something to retry against rather than orphans. The client only deletes the Cognito user *after* this returns 2xx. Don't reorder; that caused a real orphaned-household bug (`testStage5AccountDeletionActuallyDeletesHouseholdData`).
- **`BatchWriteItem` caps at 25 items** (vs Firestore's 500), and can return `UnprocessedItems` on an otherwise-successful call. Both need explicit loops.

## UI test conventions (`StarTimeUITests.swift`)

- Views expose stable accessibility identifiers for anything a label query can't uniquely target (`generatedInviteCode`, `completeChoreButton-<choreId>`, `deleteAccountRowButton`).
- Tab bar and sheet-opening taps use retry loops (`tapTab`, `tapAddButton`): a tap right after a screen transition can compute a stale hit point mid-animation and silently miss.
- Every test that creates accounts cleans them up via `deleteCurrentAccount`, including on failure paths.
- **A "Timed out while synthesizing event" failure usually means the app never went idle**, not that the element is missing — look for a repeating refetch loop or an indeterminate `ProgressView`, not a selector problem.
