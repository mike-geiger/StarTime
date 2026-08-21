# Chore Tracking Specification

## Purpose

Chores are the thing kids do to earn points: how parents define them, how recurrence decides when they are due, how completions are recorded, and how streaks are derived.

## Requirements

### Requirement: Parents define chores assigned to a household member

The system SHALL let parents create, edit, and delete chores, each with a title, icon, point value, recurrence, an assignee, and an optional ordered list of checklist items (each with a title). A chore with no checklist items completes as a single action, exactly as before; a chore with checklist items completes only once every item is checked, per the checklist requirements below. Editing and deleting SHALL be available for a chore regardless of whether it is currently due — a parent is never limited to acting only on chores that happen to be due today.

#### Scenario: Parent creates a chore

- **WHEN** a parent supplies a title, icon, point value, recurrence, and assignee
- **THEN** the chore is saved to the household and appears for that assignee

#### Scenario: Parent creates a checklist chore

- **WHEN** a parent supplies a title, icon, point value, recurrence, assignee, and a list of checklist items
- **THEN** the chore is saved with those items and appears for that assignee as a checklist

#### Scenario: Parent edits a checklist's items

- **WHEN** a parent adds, removes, or renames items on an existing chore's checklist
- **THEN** the updated list applies to future evaluation of that chore's completion

#### Scenario: Parent deletes a chore

- **WHEN** a parent deletes a chore
- **THEN** it stops appearing in chore lists, while completions already recorded against it remain in history

#### Scenario: Parent edits a chore that is not currently due

- **WHEN** a parent edits a daily or weekly chore that is not due on the day being viewed
- **THEN** the change is saved, and the chore reflects the new title, icon, point value, recurrence, or assignee wherever it is subsequently shown

### Requirement: Recurrence determines when a chore is due

The system SHALL support one-time, daily, and weekly-on-chosen-days recurrence, and SHALL show a chore as due today according to its recurrence.

#### Scenario: Daily chore

- **WHEN** a chore recurs daily
- **THEN** it is due every day until deleted

#### Scenario: Weekly chore on selected days

- **WHEN** a chore recurs weekly on a set of weekdays
- **THEN** it is due only on those weekdays

#### Scenario: One-time chore before completion

- **WHEN** a one-time chore has never been completed
- **THEN** it is due

#### Scenario: One-time chore after completion

- **WHEN** a one-time chore has been completed
- **THEN** it stops appearing as due

### Requirement: A chore counts once per calendar day

The system SHALL reject a second completion of the same chore for the same calendar day, and SHALL enforce this on the server so that concurrent or repeated requests cannot both succeed.

An interface-only check cannot hold here: a double-tap, or two devices acting at once, would each pass a local check and award points twice.

#### Scenario: Chore completed for the first time today

- **WHEN** a member completes a chore not yet completed today
- **THEN** the completion is recorded and its points are credited

#### Scenario: Same chore completed again the same day

- **WHEN** a completion is submitted for a chore already completed today
- **THEN** it is rejected, no second completion is recorded, and no additional points are credited

#### Scenario: Identical completions arrive simultaneously

- **WHEN** several identical completions for one chore and day are submitted at the same moment
- **THEN** exactly one is recorded and the points are credited exactly once

#### Scenario: Same chore on a later day

- **WHEN** a chore completed yesterday is completed today
- **THEN** the completion is recorded normally

### Requirement: The completion control cannot be triggered twice

The system SHALL disable a chore's completion control from the moment it is activated until refreshed data reflects the result, not merely once the result is known.

#### Scenario: User taps complete twice quickly

- **WHEN** a user activates the completion control twice in rapid succession
- **THEN** only one completion request is sent

### Requirement: Completions form an append-only ledger

The system SHALL record each completion as a permanent entry capturing the chore, its title, the points awarded, who completed it, when, and which calendar day it counted toward. Entries SHALL NOT be modified after creation, except that a completion MAY later be marked reversed — recording when, by whom, and an optional note — which does not remove or alter the entry's original facts about what was completed.

Recording the title and points on the entry keeps history accurate even after the chore is renamed, repriced, or deleted. Marking a reversal rather than deleting or rewriting the entry preserves that same guarantee for a completion that is later undone.

#### Scenario: Chore is renamed after completion

- **WHEN** a chore is renamed after being completed
- **THEN** existing completions still show the title as it was when completed

#### Scenario: Reversal does not alter the original record

- **WHEN** a completion is later reversed
- **THEN** its original chore, title, points, completer, and completion time remain exactly as first recorded, alongside the new reversal information

### Requirement: Streaks count consecutive days a chore was due and done

The system SHALL derive a chore's streak by counting backward over the days it was due, stopping at the first due day with no completion. A chore due today but not yet completed SHALL NOT break the streak. A day whose completion has been reversed SHALL count as not done.

#### Scenario: Chore completed several days running

- **WHEN** a daily chore was completed on each of the last several days
- **THEN** its streak equals that number of days

#### Scenario: Today's chore not yet done

- **WHEN** a daily chore was completed through yesterday but not yet today
- **THEN** the streak still reflects the run through yesterday

#### Scenario: A due day was missed

- **WHEN** a daily chore was missed two days ago but completed yesterday and today
- **THEN** the streak counts only from the miss forward

#### Scenario: Weekly chore skips days it was not due

- **WHEN** a weekly chore was completed on each of its scheduled days
- **THEN** the days it was not due do not break the streak

#### Scenario: A day's completion was reversed

- **WHEN** a chore's completion for a day within the streak was later reversed and not re-completed
- **THEN** the streak stops at that day, the same as if it had never been completed

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

The system SHALL show a member's completed chores as history — chore title, points awarded, when completed, and whether the completion was later reversed — regardless of whether that chore is currently due, currently visible as due, or has since been deleted or reconfigured. Completion history SHALL be shown alongside other progress information, not on the due-today chore list.

#### Scenario: Completed one-time chore appears in history

- **WHEN** a one-time chore has been completed
- **THEN** it no longer appears as due, but its completion is visible in history with its title, points, and completion time

#### Scenario: Completed recurring chore appears in history

- **WHEN** a daily or weekly chore has been completed on a given day
- **THEN** that completion is visible in history for that day, independent of whether the chore is also currently shown as due or as recurring

#### Scenario: History reflects the chore as it was at completion time

- **WHEN** a chore has been renamed, repriced, or deleted after being completed
- **THEN** its history entries still show the title and points that were recorded at completion time

#### Scenario: A reversed completion still appears in history

- **WHEN** a completion has been reversed
- **THEN** it remains visible in history, shown as reversed, including any note given at reversal

#### Scenario: History is not part of the due-today chore list

- **WHEN** a parent or child views the due-today chore list
- **THEN** past completions are not shown there; they appear alongside progress information instead

### Requirement: A checklist chore completes only once every item is checked

The system SHALL let a household member check or uncheck an individual item on a checklist chore for the current day, and SHALL credit the chore's points exactly once, atomically, the moment every item is checked — never per item, and never more than once for a given day, however many requests attempt it concurrently.

#### Scenario: Checking an item that does not complete the checklist

- **WHEN** a member checks one item while others remain unchecked
- **THEN** the item is recorded as checked and no points are credited

#### Scenario: Checking the item that completes the checklist

- **WHEN** a member checks the last unchecked required item
- **THEN** the chore is recorded as completed for the day and its points are credited once

#### Scenario: The last two items are checked at the same moment

- **WHEN** two different required items, both still needed to complete the checklist, are checked at the same moment by different requests
- **THEN** the chore completes exactly once and its points are credited exactly once

#### Scenario: An already-checked item is checked again

- **WHEN** a member checks an item that is already checked
- **THEN** nothing changes and no additional points are credited

#### Scenario: A non-checklist chore is unaffected

- **WHEN** a chore has no checklist items
- **THEN** it continues to complete as a single action, unaffected by checklist behavior

### Requirement: Editing a checklist's items never retroactively changes completion

The system SHALL evaluate checklist completion only at the moment a member checks or unchecks an item, or explicitly marks the chore complete — never as a side effect of editing the chore's item list. A day's completion or incompletion, once decided, SHALL NOT change because the item list was later edited, for that day or any past day.

#### Scenario: Removing an item does not retroactively complete today

- **WHEN** a parent removes an item from a chore's checklist and the remaining checked items already cover what is left required
- **THEN** the chore is not completed automatically

#### Scenario: A member can complete a checklist that editing already satisfied

- **WHEN** a checklist's checked items already cover every currently-required item, but the chore has not completed for the day
- **THEN** a member may explicitly mark it complete, crediting its points

#### Scenario: Marking complete before the checklist is satisfied is refused

- **WHEN** a member attempts to explicitly mark a checklist chore complete while a required item remains unchecked
- **THEN** the attempt is refused and no points are credited

#### Scenario: Editing items does not change a past day

- **WHEN** a chore's checklist items are edited after a previous day was completed or left incomplete
- **THEN** that past day's completion or incompletion is unchanged

### Requirement: A completed checklist chore can be reversed by unchecking an item

The system SHALL let any household member uncheck an item on a checklist chore that has already completed for the day, and SHALL treat this as a reversal: the day's completion is marked reversed, the points originally credited are debited from the assignee's balance in full, and the chore becomes completable again once every item is checked again. The debit SHALL equal the exact amount originally credited, regardless of the assignee's current balance, and SHALL NOT be refused or reduced for insufficient balance.

#### Scenario: Unchecking an item after completion reverses it

- **WHEN** a member unchecks any item on a checklist chore that already completed today
- **THEN** the day's completion is marked reversed and the assignee's balance decreases by the points that were credited

#### Scenario: Reversal can be performed by the assignee

- **WHEN** the assignee, a child, unchecks an item on their own completed chore
- **THEN** the reversal succeeds

#### Scenario: Reversal can be performed by a parent

- **WHEN** a parent unchecks an item on a child's completed chore
- **THEN** the reversal succeeds

#### Scenario: Reversal debit is not limited by balance

- **WHEN** reversing a completion would take the assignee's balance below zero, because the points were already spent
- **THEN** the reversal still succeeds and the balance goes negative

#### Scenario: Two reversal attempts at once

- **WHEN** two different items on the same completed checklist are unchecked at the same moment
- **THEN** the completion is reversed exactly once and the points are debited exactly once

#### Scenario: Re-completing after a reversal

- **WHEN** every item of a reversed checklist chore is checked again the same day
- **THEN** the chore completes again and its points are credited again

#### Scenario: A reversal accepts an optional note

- **WHEN** a member reverses a completion and supplies a note
- **THEN** the note is recorded on the reversed completion

#### Scenario: A reversal without a note

- **WHEN** a member reverses a completion without supplying a note
- **THEN** the reversal succeeds and no note is recorded

#### Scenario: Unchecking before completion is not a reversal

- **WHEN** a member unchecks an item on a checklist that has not yet completed today
- **THEN** the item is simply recorded as unchecked, and no points move

### Requirement: A chore's assignee is alerted when their completion is reversed

The system SHALL indicate to a chore's assignee when one of their completions is reversed, on that member's own device, and SHALL announce a given reversal once. It SHALL NOT announce the same reversal to the same device more than once, including across restarts of the app.

#### Scenario: A completion is reversed

- **WHEN** a household member reverses the assignee's completed chore
- **THEN** the assignee is alerted, naming the chore, on their own device

#### Scenario: Reversing your own completion still alerts you

- **WHEN** the assignee reverses their own completion
- **THEN** they are still alerted, the same as if someone else had reversed it

#### Scenario: The reversal included a note

- **WHEN** a reversal included a note
- **THEN** the alert includes that note

#### Scenario: The reversal had no note

- **WHEN** a reversal did not include a note
- **THEN** the assignee is still alerted, without a note in it

#### Scenario: Data is re-read with nothing new

- **WHEN** the app re-reads its data and a reversal it already announced has not changed again
- **THEN** no new alert is raised

#### Scenario: Assignee returns after being away

- **WHEN** the assignee opens the app after one of their completions was reversed while it was closed
- **THEN** they are alerted about it if this device has not already announced it

#### Scenario: Permission is requested only when there is something to say

- **WHEN** a member has never had a completion reversed
- **THEN** the app does not ask for permission to send notifications

#### Scenario: Permission is refused

- **WHEN** a member declines notification permission
- **THEN** their completion history still shows the reversal and its note, and the app does not ask again on its own
