## 1. Chores screen: remove Recurring and Past

- [ ] 1.1 In `ChoresView.assigneeSections(for:name:)`, delete the "Recurring" and "Past" `Section`s, leaving only "Active".
- [ ] 1.2 Delete `recurringRows(for:)`, `recurringChoreRow(_:)`, `pastRows(for:)`, `pastCompletionRow(_:)`, and `relativeDateString(for:)` from `ChoresView.swift` (relocated to their new homes in sections 2 and 3, not left behind).

## 2. Manage Chores screen

- [ ] 2.1 Create `StarTime/Views/ManageChoresView.swift`: a `NavigationStack` + `List` mirroring `ChoresView`'s parent/child section split (`ForEach(childMembers)` for a parent, self-view for a child), one `Section` per member showing `choreStore.recurringChores(for:)`.
- [ ] 2.2 Move `recurringChoreRow(_:)` onto `ManageChoresView`, keeping the `recurringChoreRow-<id>` accessibility identifier, and add the same `isParent`-gated tap-to-edit (`editingChore = chore`) and swipe-to-delete (`choreStore.deleteChore(chore)`) behavior `ChoresView.choreRow(_:)` already has for Active chores.
- [ ] 2.3 Give `ManageChoresView` its own `@State private var editingChore: Chore?` and a `.sheet(item:)` presenting `AddEditChoreView(choreStore:household:editingChore:)`, matching the pattern in `ChoresView`.
- [ ] 2.4 In `ChoresView`, add a toolbar button (e.g. `ellipsis.circle`, placed alongside the existing `+`) that pushes/presents `ManageChoresView`, visible to both parent and child (not gated by `isParent` — the button opens the screen, `isParent` gates the row actions inside it per 2.2).

## 3. Completion history in Progress

- [ ] 3.1 In `ProgressTabView`, add a "History" (or similarly named) `Section` per member — inside the existing parent `ForEach(childMembers)` block and the child self-view block — populated from `choreStore.pastCompletions(for:)`.
- [ ] 3.2 Move `pastRows(for:)`, `pastCompletionRow(_:)`, and `relativeDateString(for:)` from `ChoresView` into `ProgressTabView`, keeping the `pastCompletionRow-<id>` accessibility identifier unchanged.

## 4. Tests

- [ ] 4.1 Add a UI test that a parent can open Manage Chores from the Chores screen toolbar, tap a recurring chore, change its title or points in `AddEditChoreView`, save, and see the update reflected back in Manage Chores (and, if the chore is due today, in the Chores screen's Active section).
- [ ] 4.2 Add a UI test that a parent can swipe-delete a recurring chore from Manage Chores and it no longer appears there or in the Chores screen.
- [ ] 4.3 Add or extend a UI test asserting the Chores screen shows only the Active section (no "Recurring" or "Past" section headers).
- [ ] 4.4 Add a UI test that completion history is visible in the Progress tab for both a parent (viewing a child) and a child (viewing themselves).

## 5. Manual verification

- [ ] 5.1 Build and run in the simulator via `with-ephemeral-stack.sh`; confirm the Chores screen is uncluttered, Manage Chores lists and allows editing/deleting recurring chores, and Progress shows completion history, for both a parent and a child account.
