# Realtime Sync Specification

## Purpose

Keeping the family's devices in agreement. A chore completed on one device should appear on another without anyone reaching for a refresh, and a device that was asleep should catch up when it wakes.

## Requirements

### Requirement: Changes reach other devices in the household without user action

The system SHALL notify connected devices in a household when its data changes, and those devices SHALL update without the user refreshing.

#### Scenario: Chore completed on another device

- **WHEN** one member completes a chore while another member's device is open to the household
- **THEN** the second device reflects the completion and the updated balance without user action

#### Scenario: Change in a different household

- **WHEN** data changes in a household a device does not belong to
- **THEN** that device is not notified

### Requirement: Notifications say what changed, not what it changed to

The system SHALL notify devices which collections became stale and let them re-read, rather than delivering the changed records themselves.

Sending the data would require every client to merge updates against its own in-flight writes and to handle notifications arriving out of order. Re-reading is already what a client does after its own writes, so the same path serves both.

#### Scenario: A completion is recorded

- **WHEN** a completion is recorded, changing both the completion history and a balance
- **THEN** connected devices are told both became stale and each re-reads them

#### Scenario: Several changes land together

- **WHEN** multiple changes to a household occur in quick succession
- **THEN** devices are notified without one notification per individual record

### Requirement: Only members of a household receive its notifications

The system SHALL verify a device's identity when it connects, reject connections presenting invalid credentials, and deliver a household's notifications only to connections belonging to its members.

#### Scenario: Device connects with valid credentials

- **WHEN** a signed-in member's device connects
- **THEN** the connection is accepted and associated with their household

#### Scenario: Device connects with invalid credentials

- **WHEN** a connection presents missing, malformed, or expired credentials
- **THEN** it is refused

#### Scenario: Signed-in user without a household connects

- **WHEN** a signed-in user who belongs to no household connects
- **THEN** the connection is refused, since no notifications could be routed to it

### Requirement: A device catches up after being away

The system SHALL re-read household data and re-establish notifications when the app returns to the foreground.

A suspended app cannot observe its connection being dropped, so it cannot recover by reacting to the failure. Notifications sent while a device is asleep are not queued and are simply missed.

#### Scenario: App returns to the foreground

- **WHEN** the app becomes active after being backgrounded
- **THEN** it re-reads household data and re-establishes its connection, reflecting anything that changed while it was away

#### Scenario: App goes to the background

- **WHEN** the app is backgrounded
- **THEN** its connection is released rather than left to fail silently

### Requirement: A dropped connection recovers on its own

The system SHALL re-establish a connection lost while the app is running, backing off between attempts and capping the interval so that a sustained outage does not turn every device into a source of load.

#### Scenario: Connection drops while the app is open

- **WHEN** the connection is lost with the app still in use
- **THEN** the app re-establishes it and resumes receiving notifications

#### Scenario: Server is unreachable for a sustained period

- **WHEN** repeated attempts fail
- **THEN** the interval between attempts grows and is capped rather than retrying continuously

### Requirement: Stale connections are discarded

The system SHALL remove a connection record when delivery shows it is gone, and SHALL expire records that were never closed cleanly.

#### Scenario: Delivery finds the connection closed

- **WHEN** a notification cannot be delivered because the connection no longer exists
- **THEN** its record is removed

#### Scenario: A connection disappears without notice

- **WHEN** a device vanishes without its disconnection being observed
- **THEN** its record expires rather than persisting indefinitely

#### Scenario: One bad connection among several

- **WHEN** delivery to one connection fails while others are healthy
- **THEN** the others still receive the notification
