## MODIFIED Requirements

### Requirement: Parents define chores assigned to a household member

The system SHALL let parents create, edit, and delete chores, each with a title, icon, point value, recurrence, and an assignee. Editing and deleting SHALL be available for a chore regardless of whether it is currently due — a parent is never limited to acting only on chores that happen to be due today.

#### Scenario: Parent creates a chore

- **WHEN** a parent supplies a title, icon, point value, recurrence, and assignee
- **THEN** the chore is saved to the household and appears for that assignee

#### Scenario: Parent deletes a chore

- **WHEN** a parent deletes a chore
- **THEN** it stops appearing in chore lists, while completions already recorded against it remain in history

#### Scenario: Parent edits a chore that is not currently due

- **WHEN** a parent edits a daily or weekly chore that is not due on the day being viewed
- **THEN** the change is saved, and the chore reflects the new title, icon, point value, recurrence, or assignee wherever it is subsequently shown

### Requirement: Recurring chores are visible on days they are not due

The system SHALL show every daily or weekly chore assigned to a member, together with a human-readable description of its schedule, regardless of whether it is due on the day being viewed. This is in addition to, not a replacement for, showing it as due on the days its recurrence says it is due. Recurring chores SHALL be shown on a distinct chore-management view from the due-today list, and a parent viewing that management view SHALL be able to edit or delete any recurring chore shown there, using the same edit and delete interaction available for due-today chores.

#### Scenario: Weekly chore visible on a non-due day

- **WHEN** a chore recurs weekly on a set of weekdays that does not include today
- **THEN** it is still shown, with its scheduled weekdays, even though it is not due today

#### Scenario: Daily chore shows its schedule

- **WHEN** a chore recurs daily
- **THEN** it is shown with a schedule description indicating it recurs every day

#### Scenario: One-time chore is not shown as recurring

- **WHEN** a chore has one-time (non-recurring) recurrence
- **THEN** it is not included among the chores shown with a recurring schedule

#### Scenario: Recurring chores are absent from the due-today list

- **WHEN** a parent or child views the due-today chore list
- **THEN** daily and weekly chores not due today are not shown there; they appear only in the chore-management view

#### Scenario: Parent edits a recurring chore from the management view

- **WHEN** a parent selects a recurring chore in the chore-management view
- **THEN** they can change its title, icon, point value, recurrence, or assignee, and the update is saved

#### Scenario: Parent deletes a recurring chore from the management view

- **WHEN** a parent deletes a recurring chore from the chore-management view
- **THEN** it stops appearing in chore lists, while completions already recorded against it remain in history

### Requirement: Completion history is visible independent of current due status

The system SHALL show a member's completed chores as history — chore title, points awarded, and when completed — regardless of whether that chore is currently due, currently visible as due, or has since been deleted or reconfigured. Completion history SHALL be shown alongside other progress information, not on the due-today chore list.

#### Scenario: Completed one-time chore appears in history

- **WHEN** a one-time chore has been completed
- **THEN** it no longer appears as due, but its completion is visible in history with its title, points, and completion time

#### Scenario: Completed recurring chore appears in history

- **WHEN** a daily or weekly chore has been completed on a given day
- **THEN** that completion is visible in history for that day, independent of whether the chore is also currently shown as due or as recurring

#### Scenario: History reflects the chore as it was at completion time

- **WHEN** a chore has been renamed, repriced, or deleted after being completed
- **THEN** its history entries still show the title and points that were recorded at completion time

#### Scenario: History is not part of the due-today chore list

- **WHEN** a parent or child views the due-today chore list
- **THEN** past completions are not shown there; they appear alongside progress information instead
