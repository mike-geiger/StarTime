## 1. Model

- [x] 1.1 Add a `scheduleDescription` computed property to `Chore` (`StarTime/Models/Chore.swift`) that renders `.daily` as "Daily", `.weekly` as the selected weekdays (e.g. "Mon, Wed, Fri"), and is not used for `.once` chores.

## 2. Store

- [x] 2.1 Add `ChoreStore.recurringChores(for uid: String? = nil) -> [Chore]` returning chores with `recurrence != .once`, filtered by assignee when `uid` is given, sorted by title.
- [x] 2.2 Add `ChoreStore.pastCompletions(for uid: String? = nil) -> [ChoreCompletion]` returning `completions` filtered by `completedByUID` when `uid` is given, sorted most-recent-first.

## 3. View

- [x] 3.1 Restructure `ChoresView`'s per-assignee block (both the parent's per-child loop and the child's own-chores branch) into three consecutive `Section`s per assignee: Active, Recurring, Past — in that order.
- [x] 3.2 Wire the Active section to the existing `choresDueToday(for:)` / `choreRow(_:)` unchanged, preserving the `completeChoreButton-<choreId>` accessibility identifier and current row behavior.
- [x] 3.3 Add a Recurring row view using `recurringChores(for:)` and `Chore.scheduleDescription`, with accessibility identifier `recurringChoreRow-<choreId>`. Not completable from this section.
- [x] 3.4 Add a Past row view using `pastCompletions(for:)`, showing chore title, points, and a relative completion date, with accessibility identifier `pastCompletionRow-<completionId>`.
- [x] 3.5 Add empty-state text for Recurring ("No recurring chores yet") and Past ("No completions yet") sections, matching the existing empty-state style used for Active ("Nothing due today 🎉").

## 4. Verification

- [x] 4.1 Compile check: `xcodebuild build -project StarTime.xcodeproj -scheme StarTime -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation`.
- [x] 4.2 Run the existing UI test suite against an ephemeral stack (`backend/scripts/with-ephemeral-stack.sh`) to confirm Active-section behavior and identifiers are unaffected by the new sections.
- [x] 4.3 Manually verify in the simulator: a weekly chore not due today still appears under Recurring with its schedule; a completed one-time chore appears under Past instead of Active; a parent sees all three sections per child; a child sees all three sections for themselves.
