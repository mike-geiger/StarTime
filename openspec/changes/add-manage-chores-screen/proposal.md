## Why

The main Chores screen currently lists three sections per child — Active, Recurring, and Past — under every child's name. Active is the only section that needs daily attention; Recurring (every daily/weekly chore's template, regardless of whether it's due today) and Past (the full completion history) are reference material that crowd out the due-today list a parent actually checks first. Recurring chores are also display-only: tapping one does nothing, so a parent who needs to change a recurring chore's title, points, or schedule has no way to do it — only chores that happen to be due today are editable.

## What Changes

- Remove the "Recurring" and "Past" sections from the main Chores screen. Chores screen shows only each child's Active (due-today) chores.
- Add a "Manage Chores" screen, reached via a toolbar button on the Chores screen, listing every recurring (daily/weekly) chore per child with its schedule description.
- Recurring chores on the Manage Chores screen are editable and deletable by parents, using the same interaction as Active chores today: tap a row to open the existing add/edit sheet pre-filled, swipe to delete.
- Move the completion history (formerly the "Past" section) into the existing Progress tab, as a new section per child, read-only as before.

## Capabilities

### Modified Capabilities

- `chore-tracking`: recurring chores move to a dedicated Manage Chores screen and become editable/deletable there by parents; completion history moves to the Progress tab instead of the Chores screen.

## Impact

- **Views**: `StarTime/Views/ChoresView.swift` loses its Recurring and Past sections and gains a toolbar entry point to a new `ManageChoresView.swift` (new file, reuses `AddEditChoreView` for editing). `StarTime/Views/ProgressTabView.swift` gains a completion-history section per child.
- **Services/Stores**: No changes — `ChoreStore.recurringChores(for:)` and `ChoreStore.pastCompletions(for:)` already exist and are reused by their new callers.
- **Backend**: No changes — editing a recurring chore uses the existing `PUT /chores/{choreId}` route already used for Active chores.
- **UI tests**: `recurringChoreRow-<id>` and `pastCompletionRow-<id>` accessibility identifiers move screens; any UI test asserting their presence on the Chores screen needs updating to look on the new screens instead.
