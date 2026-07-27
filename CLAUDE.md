# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

StarTime is a SwiftUI iOS app for families to track kids' chores and reward them with points redeemable for prizes. There is no custom backend — Firebase (Auth + Firestore) is the entire server side, accessed directly from the client via the Firebase iOS SDK (added as an SPM package dependency, resolved lock is in `StarTime.xcodeproj`).

## Build & test

There's no Makefile/fastlane — use `xcodebuild` directly. The only scheme is `StarTime`.

```bash
# Build for the simulator
xcodebuild build -project StarTime.xcodeproj -scheme StarTime \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Run unit tests (StarTimeTests)
xcodebuild test -project StarTime.xcodeproj -scheme StarTime \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:StarTimeTests

# Run a single UI test
xcodebuild test -project StarTime.xcodeproj -scheme StarTime \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:StarTimeUITests/StarTimeUITests/testStage2InviteChildAndAssignChore

# Run the full UI test suite (hits a real Firebase project — see below)
xcodebuild test -project StarTime.xcodeproj -scheme StarTime \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:StarTimeUITests
```

Or just open `StarTime.xcodeproj` in Xcode and use Cmd+R / Cmd+U.

**The UI tests are integration tests against live Firebase**, not a local emulator — `StarTimeUITests.swift` signs up real (timestamp-suffixed, e.g. `test-\(Int(Date().timeIntervalSince1970))@example.com`) accounts, creates real households, and exercises the full invite/chore/reward flow end to end. Every test cleans up after itself by deleting the accounts it created (which cascades to deleting the household once the last member leaves — see `HouseholdService.leaveHousehold`). If a test fails mid-run, it can leave orphaned test accounts/households behind in Firebase.

Firestore security rules are **not** part of this repo — they live in the Firebase console/project config only. Keep this in mind when a change touches read/write patterns (e.g. new queries, new collections): there's no local rules file to check against, and a rules mismatch will only surface as a runtime permission error (as it did historically — see the comment on `testStage5AccountDeletionActuallyDeletesHouseholdData`).

`StarTime/GoogleService-Info.plist` is required for the app to run (`FirebaseApp.configure()` in `StarTimeApp.swift` reads it) but is untracked/local-only — it won't be present in a fresh checkout and shouldn't be assumed to exist.

## Architecture

Each feature area (household, chores, rewards) follows the same three-layer pattern:

**Model → Service → Store → View**

- **Models** (`StarTime/Models/`): plain `Codable` structs mirroring Firestore documents, using `@DocumentID` / `@ServerTimestamp` property wrappers (e.g. `Chore`, `Reward`, `Household`). No logic beyond the occasional static list of UI choices (`Chore.iconChoices`).
- **Services** (`StarTime/Services/*Service.swift`): stateless structs that are the only code allowed to touch `Firestore.firestore()` / `Auth.auth()` directly. They expose async throwing functions for one-off reads/writes and `addSnapshotListener`-based `...Listener(...)` functions for live data. Views never call these directly.
- **Stores** (`StarTime/Services/*Store.swift`): `@MainActor final class ... ObservableObject`, one per feature (`HouseholdStore`, `ChoreStore`, `RewardStore`). Own a `Service` instance, hold `@Published` state, manage listener lifecycle (`start(householdId:)` / `stop()`), swallow service errors into an `errorMessage: String?` published property, and expose derived/computed view logic (e.g. `ChoreStore.streak(for:)`, `ChoreStore.choresDueToday(for:)`, `RewardStore.balance(for:)`). Views read state and call methods on stores; stores never talk to views.
- **Views** (`StarTime/Views/`): SwiftUI views injected with stores via `.environmentObject`.

App-level composition root is `StarTimeApp.swift` (calls `FirebaseApp.configure()`, owns the single `AuthService`) → `ContentView.swift` (the auth/onboarding gate: routes between `AuthView` → `HouseholdSetupView` → `MainTabView` based on `AuthService.user` and `HouseholdStore.household`) → `MainTabView.swift` (the four tabs: Chores, Rewards, Progress, Settings, each owning/receiving its own store).

### Firestore data model

```
users/{uid}                              — UserProfile: {name, householdId?, role?}
                                            One doc per signed-in user, purely so the
                                            app can find "my household" with a single
                                            cheap read instead of scanning households.
households/{id}                          — Household: {name, members: {uid: {name, role}}, lastJoinCode?}
households/{id}/chores/{choreId}         — Chore
households/{id}/completions/{id}         — ChoreCompletion (one doc per completion event)
households/{id}/rewards/{rewardId}       — Reward
households/{id}/redemptions/{id}         — Redemption (one doc per redemption event)
inviteCodes/{6-char code}                — InviteCode: {householdId, role, createdByUID}
```

Key conventions to preserve when touching this data:

- **Point balances are never stored** — `RewardStore.balance(for:)` derives them by summing `ChoreCompletion.pointsAwarded` minus `Redemption.pointsSpent` from the live listeners. Completions/redemptions are an append-only ledger, not mutated after creation.
- **Streaks are computed client-side** in `ChoreStore.streak(for:)` by walking backward day-by-day (or due-day-by-due-day for weekly chores) through completions matched on the `scheduledDate` ("yyyy-MM-dd") field, not `completedAt`. `ChoreService.dayString(_:)` is the canonical formatter for that field — always use it rather than formatting dates ad hoc, since completions are matched by exact string equality.
- **`ChoreStore` and `RewardStore` both listen to the same `completions` subcollection** but via different queries: `ChoreService.completionsListener` scopes to the last 60 days (enough for any realistic streak); `RewardService.completionsListener` has no cutoff (balances are cumulative for life). Don't consolidate these without preserving that distinction.
- **Deleting the last household member cascades**: `HouseholdService.leaveHousehold` deletes all chores/completions/rewards/redemptions/invite codes and the household doc itself when the leaving member was the only one left. Account deletion (`HouseholdStore.deleteAccountData`) always calls this before removing the Firebase Auth user, and deliberately returns `false` (aborting the Auth deletion) if the Firestore cleanup throws — don't reorder that so Auth deletion happens first, since it previously caused the orphaned-household bug covered by `testStage5AccountDeletionActuallyDeletesHouseholdData`.

### UI test conventions (`StarTimeUITests.swift`)

- Views expose stable accessibility identifiers for elements a `staticTexts`/`buttons` label query can't uniquely target (e.g. `generatedInviteCode`, `completeChoreButton-<choreId>`, `deleteAccountRowButton`) — keep using identifiers rather than label text for anything dynamic or duplicated on screen.
- Tab bar and sheet-opening taps use retry loops (`tapTab`, `tapAddButton`) instead of a single tap, because a tap immediately after a screen transition can compute a stale hit point mid-animation and silently miss. Follow the same retry pattern for any new interaction that fires right after a navigation/transition.
- Every test that creates accounts/households cleans them up via `deleteCurrentAccount` before returning, including on the "expected failure" path — don't add a test that leaves live data behind in the Firebase project.
