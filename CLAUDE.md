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

**Get that UDID from `xcodebuild -showdestinations`, immediately before the test run — never from `xcrun simctl list devices`, and never reused from earlier in a session.**

```bash
xcodebuild -scheme StarTime -showdestinations -project StarTime.xcodeproj 2>&1 | grep -i "iOS Simulator.*iPhone"
```

`simctl list devices available` enumerates every simulator instance that exists at the OS level, including stale clones left behind by earlier `xcodebuild test` runs — a session that has run tests a few times can easily show three or four differently-UDID'd "iPhone 17" entries, all "available," only one of which `xcodebuild` will actually resolve right now. `-showdestinations` is scheme-aware and reports exactly what this build will accept at this moment, which is why it reliably shows only the live one. This is a repeat failure mode, not a hypothetical: a UDID picked from `simctl list` earlier in a session — even one that resolved fine minutes before — can silently stop resolving (`xcodebuild: error: Unable to find a destination matching the provided destination specifier`) by the time a long-running deploy-then-test invocation actually gets to it. Re-run the `-showdestinations` query right before the `xcodebuild test` call itself, not once at the start of a session.

Some behavior can't be tested through XCUITest at all, because the suite drives a single client. Those have dedicated Node scripts under `backend/cdk/scripts/`, run the same way (they read the `STARTIME_*` env vars):

- `verify-realtime.mjs` — opens a WebSocket, writes over REST, asserts the pushed invalidation arrives. Covers authorizer → `$connect` → Streams → fan-out.
- `verify-duplicate-guard.mjs` — fires 5 identical completions concurrently, asserts exactly one 201 and four 409s.
- `verify-checklist-completion.mjs` — checks a checklist chore's items one at a time and asserts credit lands exactly once, only on the item that closes the set, including when two different "last items" are checked at the same moment; reverses a completed checklist (with the balance going negative when the points were already spent) and re-completes it; and asserts editing a chore's items never auto-completes a day, only the explicit complete action does.
- `verify-migration-shape.mjs` — writes items straight into DynamoDB, bypassing every handler, then reads them back through the API. Catches what the UI tests can't: they only read back what the handlers themselves wrote, so a sort key outside a query's range or a missing GSI attribute would pass unnoticed. Relevant to anything that writes to the table out-of-band (backfill, repair, restore).
- `verify-redemption-lifecycle.mjs` — drives a redemption through its fulfillment states using **two** identities, a parent and a child. Asserts the child's token is 403 on every transition, that five concurrent cancels refund exactly once, and that a status-less legacy row reads as fulfilled.
- `verify-deployment-marker.mjs` — asserts `/health` reports the commit and dirty flag the stack was actually built from, that a deliberately wrong expected commit is detected as a mismatch, and that an unreachable endpoint never reads as a match. The same comparison `deploy-prod.sh` makes against prod, run here against a throwaway stack.

They live under `backend/cdk/` because ESM resolves imports relative to the file, and `node_modules` is there.

### Cost/latency note

Each ephemeral run deploys and destroys real AWS resources — typically ~1–3 minutes each way, longer under throttling. Prefer targeting a single test while iterating.

### Installing on a physical device

The family's iPhone and iPad are updated by building a Release build pointed at the **persistent `prod` stack** (not an ephemeral one — those get destroyed on exit) and pushing it straight to the device, no App Store / TestFlight involved. Code signing is `Automatic` with a `DEVELOPMENT_TEAM` already set in the project, so `-allowProvisioningUpdates` is enough for Xcode to handle it.

1. Confirm prod is actually current: compare `git rev-parse --short HEAD` against `commit` from prod's `/health` (`ApiBaseUrl`'s sibling `HealthApiUrl` in `backend/cdk/outputs/prod.json`). If they differ, that's a `backend/scripts/deploy-prod.sh` call, not a rebuild — deploy prod first (confirm with the user; see the script's own warnings about `prod` having no teardown path).
2. Confirm the device is actually reachable — `xcrun xctrace list devices` can report a plugged-in device as offline from a stale cache; `xcrun devicectl list devices` reflects live state (`available (paired)`).
3. Get each destination's `id` via `xcodebuild -scheme StarTime -showdestinations -project StarTime.xcodeproj` — it's a different UDID format than the one `xctrace`/`devicectl` print.
4. Derive the `STARTIME_*` build settings from `backend/cdk/outputs/prod.json` (`StarTime-Auth-prod`, `StarTime-Api-prod.ApiBaseUrl`, `StarTime-Realtime-prod.WebSocketUrl` — split each URL into scheme/host per the "Configuration" section below), and build straight to a device destination:
   ```bash
   xcodebuild build -project StarTime.xcodeproj -scheme StarTime \
     -destination 'id=<DEVICE_UDID>' -configuration Release \
     -derivedDataPath build/<device-name> \
     -skipPackagePluginValidation -allowProvisioningUpdates \
     STARTIME_USER_POOL_ID=... STARTIME_USER_POOL_CLIENT_ID=... STARTIME_AWS_REGION=us-west-2 \
     STARTIME_API_SCHEME=https STARTIME_API_HOST=... STARTIME_WS_SCHEME=wss STARTIME_WS_HOST=...
   ```
5. Install the built `.app` (under `build/<device-name>/Build/Products/Release-iphoneos/StarTime.app`) with `xcrun devicectl device install app --device <DEVICE_UDID> <path-to-.app>` — `xcodebuild build` only compiles, it doesn't push to the device.

`-derivedDataPath build/...` output is multi-GB per target and gitignored (`/build/`); delete it after installing, it's disposable.

## Configuration

The app has no hardcoded endpoints. `StarTime/Config/StarTime.xcconfig` declares build settings that `SupportingFiles/Info.plist` interpolates, and `BackendConfig.swift` reads them (with a `ProcessInfo.environment` override for launch-time swapping).

**`Info.plist` lives in `SupportingFiles/`, deliberately outside `StarTime/`.** That folder is an Xcode 16 synchronized group, which auto-sweeps everything under it into Copy Bundle Resources — including the Info.plist, causing "Multiple commands produce Info.plist". Resource-phase membership exceptions do *not* reliably suppress this; relocating the file is the fix.

**A URL can't live in an xcconfig** — `//` starts a comment. Hence the split `STARTIME_API_SCHEME`/`STARTIME_API_HOST` pair, recombined in Info.plist.

## Architecture

Each feature area (household, chores, rewards) follows the same layering:

**Model → Service → Store → View**

- **Models** (`StarTime/Models/`): plain `Codable` structs mirroring the JSON the Lambdas return. Timestamps are ISO8601 **with fractional seconds** (`new Date().toISOString()`), which Swift's stock `.iso8601` strategy rejects — `APIClient` installs a custom decoding strategy for this, **and a matching custom encoding strategy**, deliberately kept in sync. Any struct carrying a previously-*decoded* `Date` (i.e. an edit of an existing record — creation always sends `nil`) round-trips that field through the encoder too; without a matching strategy it silently falls back to `.deferredToDate` (a raw number), which the backend stores as-is, so the write itself succeeds — but the *next* GET of that record now has a number where the decoder requires a string, decoding throws, and (since background refetch failures are swallowed by design, see below) the store's published state simply freezes with zero user-visible symptom. Found via direct CloudWatch inspection of a PUT body after edited-chore fields silently stopped persisting.
- **Services** (`StarTime/Services/*Service.swift`): stateless structs wrapping `APIClient`. They own endpoint paths and map HTTP status codes to domain errors (404 → `HouseholdServiceError.invalidCode`, 409 → `RewardServiceError.insufficientBalance` / "already completed today"). Views never call these directly.
- **Stores** (`StarTime/Services/*Store.swift`): `@MainActor final class ... ObservableObject`. Hold `@Published` state, expose `start(householdId:)`/`stop()`/`refresh()`, and own derived view logic (`ChoreStore.streak(for:)`, `choresDueToday(for:)`, `RewardStore.balance(for:)`).
- **Views** (`StarTime/Views/`): SwiftUI, injected with stores via `.environmentObject`.

`APIClient` (`StarTime/Services/APIClient.swift`) is a `@MainActor` singleton: URLSession, bearer-token auth, typed decode, and a single 401-refresh-retry. Its `tokenProvider` is wired in `AuthService.init()` — **not** from the App body, because a `.task`-based assignment races the first request.

Composition root: `StarTimeApp.swift` (owns `AuthService`) → `ContentView.swift` (auth/onboarding gate) → `MainTabView.swift` (owns the **shared** `ChoreStore`, `RewardStore`, `RealtimeConnectionManager`, `PendingRedemptionNotifier`, `RewardReversalNotifier`, and `ChoreCompletionReversalNotifier`).

### Conventions that are load-bearing

- **Stores are shared, not per-view.** `ChoreStore`/`RewardStore` are `@StateObject`s on `MainTabView`, injected downward. They used to be per-view, which Firestore's snapshot listeners silently compensated for by pushing every write to every instance. With fetch-based stores, a write through one instance is invisible to the others — sharing is a correctness requirement now.
- **`observe(_:)` subscriptions must not be torn down by `stop()`.** `start()` calls `stop()` internally, so clearing the subscription there unsubscribes the store from all realtime pushes — a bug that made the entire realtime layer silently dead while the backend looked healthy. `refresh()` no-ops without a household, so a late invalidation is harmless.
- **Never refetch in response to a `@Published` change of a store the view observes.** `RewardsView.onAppear { refresh() }` fed back into `MainTabView`'s re-render, which re-fired `onAppear`; the app never went idle and XCUITest stalled for 900+ seconds per tap. Cross-store updates travel via realtime invalidation instead. `PendingRedemptionNotifier`, `RewardReversalNotifier`, and `ChoreCompletionReversalNotifier` all subscribe to a store's `@Published` collection and are bound by the same rule — they read and post, never refetch, and deliberately declare no `@Published` state so none can re-render the view that owns the stores. `RewardReversalNotifier` alerts the *redeeming member* (filtered by uid, not role) when one of their own redemptions is cancelled or un-fulfilled, including the optional note in the alert body when one was given; `ChoreCompletionReversalNotifier` does the same for a chore's *assignee* when one of their completions is reversed (even if the assignee performed the reversal themselves — see below), reading `ChoreStore.$completions` instead. Neither reversal notifier installs itself as the `UNUserNotificationCenter` delegate, since only one delegate can be active at a time and `PendingRedemptionNotifier` already claims that role for the app — its `willPresent` handler isn't scoped to the notifications it personally posts, so both still show as foreground banners as long as that notifier is also running, which `MainTabView` guarantees for every session regardless of role. Each reversal notifier's de-dup key is `id` plus its own timestamp field (`cancelledAt`/`unfulfilledAt` for redemptions, `reversedAt` for completions) rather than bare id, since neither reversal is terminal and the same entry can need a fresh announcement more than once.
- **`ChoreService.dayString(_:)` is the canonical `scheduledDate` formatter.** Completions are matched by exact string equality on it (streaks, once-per-day). Never format that date ad hoc.
- **Background refetch failures are not user-facing.** Only user-initiated actions populate `errorMessage`; a transient failure raised as a modal alert blocks UI interaction (including XCUITest taps). `ChoresView` now surfaces `choreStore.errorMessage` the same way `RewardsView` does — it previously had no error alert at all, so a failed check/uncheck or save silently no-op'd from the user's perspective.
- **`ChoreStore.refreshNow()` is guarded against out-of-order responses with a generation counter.** Two overlapping refreshes (e.g. a realtime invalidation landing mid-way through a manual `refresh()`) race on the network, not in program order; without a check, a slower *older* response can overwrite state a newer one already wrote. `refreshNow()` increments `refreshGeneration` before issuing requests and discards the result if the counter has moved on by the time they land — apply the same pattern to any other store method that awaits multiple fetches before publishing.
- **A checklist chore's completion is decided once, at write time, and never revisited.** `ChoresView` shows per-item checkboxes instead of a single Complete button whenever `Chore.items` is non-empty. Checking/unchecking an item is always a cheap, unconditional, idempotent write (`ADD`/`DELETE` on a native DynamoDB String Set); only the *evaluation* of whether that write closes or reopens the day attempts the conditional transaction that actually moves points — see `check-checklist-item.ts`/`uncheck-checklist-item.ts`/`complete-checklist.ts` and `openspec/changes/add-chore-checklists/design.md` for why this two-step shape is what makes two different "last items" checked at the same moment resolve safely without a retry loop. Editing a chore's item list (`AddEditChoreView`) never itself completes or un-completes a day — `ChoreStore.markChecklistComplete` is a distinct, explicit action for the one case that needs it: an edit leaving the already-checked items covering everything left required, with no unchecked item left to tap.

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

**`GET /health` reports what is deployed, not just that something is.** It's unauthenticated and returns `{status, stage, commit, dirty}` — `commit`/`dirty` are resolved once in `bin/startime.ts` via `git rev-parse --short HEAD` / `git status --porcelain` at synth time (a bundled Lambda has no git metadata of its own) and set as env vars on the health Lambda only. `deploy-prod.sh` curls it after every deploy and fails if the reported commit doesn't match local `HEAD` — a deploy that reports success but never actually served the new code is exactly the failure this catches. Kept off every other Lambda deliberately: a commit baked into all twenty-odd functions' environments would put a diff line on each of them on every commit, burying real changes in the `cdk diff` the script prints before asking to confirm. No build timestamp either, for the same reason — it would diff on every synth, even a re-deploy of the identical commit.

**`cdk diff` must run against the default `cdk.out`, not a custom `--output`.** `RestLambda` bundles with `sourceMap: true`, which embeds absolute paths; synthesizing to a different output directory changes those paths and therefore every asset hash, so the diff reports all five stacks as changed when nothing actually differs from what's deployed. This produced a real false alarm mid-session — a `cdk diff --output /tmp/...` run looked like an incomplete rollout until re-run against the default directory showed zero differences.

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
Checklist progress      PK=HOUSEHOLD#{id}      SK=CHECKLIST#{choreId}#{scheduledDate}
Invite code             PK=INVITECODE#{code}   SK=METADATA   GSI1PK=HOUSEHOLD#{id}  GSI1SK=INVITECODE#{code}
```

- **A redemption carries its fulfillment state as attributes on that same item**: `status` (`pending`/`fulfilled`/`cancelled`), plus `fulfilledAt`/`fulfilledByUID`/`fulfilledByName` and `cancelledAt`/`cancelledByUID`. No new item shape and no index — the parent's queue is the redemption range filtered to `pending`.
- **Cancelling and un-fulfilling accept an optional `note` (capped at 500 characters), stored as `reversalNote`.** It's a single field, not one per transition: whichever of the two reversals happened most recently owns it, and fulfilling removes it — a note only ever describes the *current* reversal, never a superseded one. Un-fulfilling also stamps `unfulfilledAt`, which — unlike `cancelledAt` — isn't display data; it exists only so `RewardReversalNotifier` (below) can tell one un-fulfil event on the same redemption from the next, since un-fulfilling isn't terminal the way cancelling is. A note sent alongside `status: 'fulfilled'` is silently ignored, not an error.
- **A missing `status` means `fulfilled`, and that default lives in exactly one place**: `presentRedemption` in `lambda/rewards/redemptions.ts`, applied on read. Every redemption predating fulfillment tracking was complete when it was made, so defaulting them to pending would hand existing families a queue of obligations they'd already met. There's no backfill; the write path tolerates the absent attribute via `attribute_not_exists(#status) OR #status = :fulfilled` on the un-fulfil transition only.
- **A redemption can't be point-read by id** — its sort key is `REDEMPTION#{redeemedAtISO}#{id}`, so `findRedemptionById` range-queries and matches on the `id` attribute. Scoping that query to the caller's own household is what makes another household's redemption a 404 rather than a leak.
- **Range queries need an explicit upper bound.** Completions/redemptions use `SK BETWEEN 'COMPLETION#{since}' AND 'COMPLETION#~'`. A bare `SK > :since` also matches `METADATA`/`REWARD#`/etc. under the same PK.
- **`COMPLETEDON#` sorts before `COMPLETION#`** (`'E' < 'I'`), so markers fall outside the completion range and never leak into results. They *are* invisible to `begins_with('COMPLETION#')` too — cascade delete names them explicitly.
- **GSI1 exists for one query**: finding a household's invite codes during cascade delete.
- **A chore's `items` (`{id, title}[]`) gate its completion instead of a single tap.** Items carry no point value of their own — only the whole chore's completion credits points, exactly once, per `scheduledDate`. Ids are generated client-side (`AddEditChoreView`, `UUID().uuidString`); there's no per-item endpoint, items travel through the existing whole-object `PUT`/`POST /chores` overwrite. `list-chores.ts` defaults a pre-existing chore's missing `items` attribute to `[]` on read — the same "absence defaults to the pre-feature meaning" rule as a status-less redemption — so every chore written before this shipped decodes and behaves exactly as a single-tap chore.
- **The `COMPLETEDON#` marker also stores `completedAt`, alongside its existing `completionId`.** Together they reconstruct a completion's exact `SK` (`COMPLETION#{completedAt}#{completionId}`), which is what lets checklist reversal (`uncheck-checklist-item.ts`) find and update the specific completion it needs to reverse with a point `GetItem`/`Update` rather than a range query.
- **A checklist chore's completion is normally reversible, unlike a single-tap chore's.** Unchecking an item on a checklist that already completed today marks the `ChoreCompletion` reversed (`reversedAt`/`reversedByUID`/optional `reversalNote`, capped at 500 characters like a redemption's) rather than deleting or rewriting it — completions are append-only *except* for this one recorded exception — debits the assignee's balance by exactly the points that were credited (uncapped: the balance can go negative if those points were already spent), and deletes the `COMPLETEDON#` marker so the day can complete again once every item is re-checked. Any household member may do this, including the assignee undoing their own mis-tap — there's no new role restriction, matching how `record-completion.ts` already lets any member complete a chore on anyone's behalf.

### Authorization

Firestore's console-only security rules are gone; **authorization now lives in version-controlled Lambda code**. Every handler derives the caller's identity from `custom:legacy_uid` in the authorizer-validated token claims (`common/auth.ts`) and re-derives their `householdId` server-side. **Never trust a client-supplied uid or householdId.**

**`custom:legacy_uid`, not Cognito's `sub`, is the canonical app-level user id.** Set by the `PostConfirmation` trigger at sign-up, for every account. The name is historical — `sub` is regenerated per user pool, so data keyed on it could never have survived the provider change; a separate stable id is what let existing households stay reachable.

**`requireParent(householdId, uid, message)` in `common/auth.ts` is the parent-role check**, used by `generate-invite-code.ts` and `update-redemption-status.ts`. It reads the household `METADATA` item's member map, not the `role` copy on the user profile — the profile's is a per-user denormalization; the member map is the household's own record. It returns the member so a caller can attribute an action without a second read.

**The App Client uses `USER_PASSWORD_AUTH`, not SRP, and that's load-bearing.** `AuthService.signIn` calls `InitiateAuth` with `.userPasswordAuth`, and aws-sdk-swift ships no SRP implementation (it's in Amplify, which this app doesn't use). Enabling SRP and disabling this breaks sign-in. It was originally chosen so the since-removed migration trigger could verify plaintext passwords against Firebase, but the client now depends on it independently.

### Realtime

DynamoDB Streams → fan-out Lambda → WebSocket push of a **lightweight invalidation** (`{"type":"invalidate","resources":["chores","balances"]}`), not the changed data. Clients refetch. This avoids merge/ordering logic entirely and matches how the stores already behave after their own writes.

- **WebSocket Lambda authorizers must return an IAM policy document.** The simple `{ isAuthorized: true }` shape is HTTP-API-only; returning it from a WebSocket authorizer fails the handshake with a bare 1006 close and no diagnostic.
- **The ID token rides in `?token=`**, because native WebSocket handshakes can't set headers. It would appear in API Gateway access logs if those were enabled.
- **iOS suspends backgrounded apps and kills the socket without the app observing the failure**, so it can't self-heal via the reconnect path. `MainTabView` refetches and reconnects on `scenePhase == .active`. A push sent to a sleeping device is simply lost — there's no queue.
- **`CHECKLIST#` items are classified as the `chores` resource** in `stream-fanout.ts`'s `resourceFor`, not a resource of their own — `ChoreStore` already refetches on a `chores` invalidation, so checklist progress needs no new client-side subscription.

### Invariants worth preserving

- **Balances are a denormalized counter**, updated in the same `TransactWriteItems` as the completion/redemption that justifies them. They must never drift from the ledger.
- **Redemption is atomic**: the balance decrement carries `ConditionExpression: balance >= :cost`, so the write itself enforces sufficiency. The old client-side pre-check could be beaten by two concurrent redemptions.
- **One completion per chore per day** is enforced by a conditional `Put` of the `COMPLETEDON#` marker in the same transaction. A completion's own sort key carries a timestamp and uuid and can never collide, so it can't be the constraint. `verify-duplicate-guard.mjs` proves this under concurrency.
- **A checklist chore's closing credit fires exactly once, however many checks race to close it.** Checking an item is two independent writes, not one transaction: an unconditional `ADD` to the checklist-progress item's `checkedItemIds` set, then a *strongly consistent* re-read compared against the chore's current `items`. If two different items are each other's last missing piece and get checked at the same moment, a naive "read current, decide, write" implementation can drop the credit entirely — DynamoDB serializes writes to a single item, so requiring the re-read to be strongly consistent and to happen after the item's own write commits is what guarantees whichever write lands second observes the other's already-landed contribution and wins the same `COMPLETEDON#`-marker-guarded closing transaction `record-completion.ts` uses. The earlier write's re-read correctly sees no completion, since the set genuinely wasn't complete yet at that instant. Reversal (unchecking a completed checklist) is the mirror image: an unconditional `DELETE` from the set, then — only if a `COMPLETEDON#` marker exists — a reversal transaction gated by `attribute_not_exists(reversedAt)` on the completion, so two concurrent unchecks on a completed checklist reverse it exactly once. `verify-checklist-completion.mjs` proves both races under concurrency.
- **`pending → cancelled` is the only path that returns points**, and the refund rides in the same `TransactWriteItems` as the status change, conditioned on `status = 'pending'`. That condition is the only thing between one cancel and a double refund. `fulfilled → cancelled` is deliberately refused (un-fulfil first) so a second refund path never has to exist, and the amount comes from the redemption's own `pointsSpent` — never re-read from the reward, which may have been repriced or deleted. `verify-redemption-lifecycle.mjs` proves this under concurrency, and now also covers the optional reversal note (present, absent, over the 500-character cap, and ignored on a `fulfilled` target) and `unfulfilledAt` changing across repeated un-fulfils of the same redemption.
- **`PATCH /redemptions/{redemptionId}` carries a target state, not a verb.** Each of the three legal targets has exactly one legal origin, which the `ConditionExpression` names — so the locating read can't be raced, and `cancelled` is terminal for free because no transition names it as an origin. Fulfil/un-fulfil use `ReturnValues: ALL_NEW`, and cancel re-reads with `ConsistentRead`: a default Query right after a write can return the pre-write item.
- **Cascade delete ordering**: `DELETE /account` removes completions, markers, checklist progress, redemptions, chores, rewards, balances, invite codes (via GSI1), then the household — household last, so a partial failure leaves something to retry against rather than orphans. The client only deletes the Cognito user *after* this returns 2xx. Don't reorder; that caused a real orphaned-household bug (`testStage5AccountDeletionActuallyDeletesHouseholdData`).
- **`BatchWriteItem` caps at 25 items** (vs Firestore's 500), and can return `UnprocessedItems` on an otherwise-successful call. Both need explicit loops.

## UI test conventions (`StarTimeUITests.swift`)

- Views expose stable accessibility identifiers for anything a label query can't uniquely target (`generatedInviteCode`, `completeChoreButton-<choreId>`, `deleteAccountRowButton`, `pendingRedemptionRow-<id>`, `fulfillRedemptionButton-<id>`, `cancelRedemptionButton-<id>`, `unfulfillRedemptionButton-<id>`, `checklistItemCheckbox-<choreId>-<itemId>`, `markChecklistCompleteButton-<choreId>`, `checklistItemTitleField-<index>` — the last because every row in `AddEditChoreView`'s item editor shares the same "Item" placeholder, so a UI test can't otherwise tell them apart).
- **Tests that produce a pending redemption, or check off a checklist chore, must launch via `makeApp()`**, which sets `STARTIME_SUPPRESS_NOTIFICATION_PROMPT=1`. `PendingRedemptionNotifier` asks for notification permission the first time a parent's queue fills, and `RewardReversalNotifier`/`ChoreCompletionReversalNotifier` do the same the first time a redemption or completion is reversed; any of these SpringBoard alerts would otherwise appear mid-suite and swallow the next tap. Only the prompt is suppressed — the queue, both badges, and the reversal note UI all still work, so nothing under test is stubbed out.
- Tab bar and sheet-opening taps use retry loops (`tapTab`, `tapAddButton`): a tap right after a screen transition can compute a stale hit point mid-animation and silently miss.
- Every test that creates accounts cleans them up via `deleteCurrentAccount`, including on failure paths.
- **A "Timed out while synthesizing event" failure usually means the app never went idle**, not that the element is missing — look for a repeating refetch loop or an indeterminate `ProgressView`, not a selector problem.
- **A SwiftUI `Toggle` inside a `Form` row exposes a nested accessibility tree**: the outer element XCUITest finds by label (`app.switches["Use a checklist"]`) is a row-wide wrapper that reports `isHittable == false` and never actually flips regardless of tap technique (plain tap, coordinate offset, `.press(forDuration:)`); the real, tappable `Switch` is an unlabeled child. Scope into it explicitly: `app.switches["Use a checklist"].switches.firstMatch.tap()`.
- **The system "Save Password?" prompt can appear well after the point it's normally dismissed**, not just immediately after a sign-in/sign-up. A test that dismisses it once right after auth can still get blocked by it reappearing before a later tap — call `dismissSavePasswordPromptIfPresent` again at any point a subsequent tap unexpectedly reports "not hittable"; check `app.debugDescription` for a stray `Button, label: 'Not Now'`/`'Save'` to confirm before chasing a different cause.
