## ADDED Requirements

### Requirement: Recurring chores are visible on days they are not due

The system SHALL show every daily or weekly chore assigned to a member, together with a human-readable description of its schedule, regardless of whether it is due on the day being viewed. This is in addition to, not a replacement for, showing it as due on the days its recurrence says it is due.

#### Scenario: Weekly chore visible on a non-due day

- **WHEN** a chore recurs weekly on a set of weekdays that does not include today
- **THEN** it is still shown, with its scheduled weekdays, even though it is not due today

#### Scenario: Daily chore shows its schedule

- **WHEN** a chore recurs daily
- **THEN** it is shown with a schedule description indicating it recurs every day

#### Scenario: One-time chore is not shown as recurring

- **WHEN** a chore has one-time (non-recurring) recurrence
- **THEN** it is not included among the chores shown with a recurring schedule

### Requirement: Completion history is visible independent of current due status

The system SHALL show a member's completed chores as history — chore title, points awarded, and when completed — regardless of whether that chore is currently due, currently visible as due, or has since been deleted or reconfigured.

#### Scenario: Completed one-time chore appears in history

- **WHEN** a one-time chore has been completed
- **THEN** it no longer appears as due, but its completion is visible in history with its title, points, and completion time

#### Scenario: Completed recurring chore appears in history

- **WHEN** a daily or weekly chore has been completed on a given day
- **THEN** that completion is visible in history for that day, independent of whether the chore is also currently shown as due or as recurring

#### Scenario: History reflects the chore as it was at completion time

- **WHEN** a chore has been renamed, repriced, or deleted after being completed
- **THEN** its history entries still show the title and points that were recorded at completion time
