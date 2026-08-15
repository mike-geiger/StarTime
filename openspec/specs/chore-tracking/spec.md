# Chore Tracking Specification

## Purpose

Chores are the thing kids do to earn points: how parents define them, how recurrence decides when they are due, how completions are recorded, and how streaks are derived.

## Requirements

### Requirement: Parents define chores assigned to a household member

The system SHALL let parents create, edit, and delete chores, each with a title, icon, point value, recurrence, and an assignee.

#### Scenario: Parent creates a chore

- **WHEN** a parent supplies a title, icon, point value, recurrence, and assignee
- **THEN** the chore is saved to the household and appears for that assignee

#### Scenario: Parent deletes a chore

- **WHEN** a parent deletes a chore
- **THEN** it stops appearing in chore lists, while completions already recorded against it remain in history

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

The system SHALL record each completion as a permanent entry capturing the chore, its title, the points awarded, who completed it, when, and which calendar day it counted toward. Entries SHALL NOT be modified after creation.

Recording the title and points on the entry keeps history accurate even after the chore is renamed, repriced, or deleted.

#### Scenario: Chore is renamed after completion

- **WHEN** a chore is renamed after being completed
- **THEN** existing completions still show the title as it was when completed

### Requirement: Streaks count consecutive days a chore was due and done

The system SHALL derive a chore's streak by counting backward over the days it was due, stopping at the first due day with no completion. A chore due today but not yet completed SHALL NOT break the streak.

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
