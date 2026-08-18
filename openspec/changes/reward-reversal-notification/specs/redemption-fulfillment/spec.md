## MODIFIED Requirements

### Requirement: Fulfillment state changes only along defined transitions

The system SHALL permit a redemption to move from pending to fulfilled, from fulfilled back to pending, and from pending to cancelled. Every other transition SHALL be refused, and cancelled SHALL be final. A transition SHALL be applied only if the redemption is still in the state the transition starts from. Un-fulfilling and cancelling SHALL accept an optional note from the parent performing the transition, which SHALL be recorded on the redemption; fulfilling SHALL NOT accept one.

Requiring the starting state is what makes concurrent attempts safe: two parents resolving the same request at the same moment must not both take effect, particularly when one of them is a cancellation that returns points.

#### Scenario: Parent marks a pending redemption fulfilled

- **WHEN** a parent fulfills a pending redemption
- **THEN** it becomes fulfilled, recording which parent resolved it and when

#### Scenario: Fulfilling clears a stale reversal note

- **WHEN** a parent fulfills a redemption that carries a note from an earlier reversal
- **THEN** it becomes fulfilled and the note no longer appears on it

#### Scenario: Parent reverts an accidental fulfillment

- **WHEN** a parent un-fulfills a redemption they marked fulfilled by mistake
- **THEN** it returns to pending and reappears among the requests waiting on them

#### Scenario: Parent cancels a pending redemption

- **WHEN** a parent cancels a pending redemption
- **THEN** it becomes cancelled and leaves the pending queue

#### Scenario: Parent cancels a redemption already fulfilled

- **WHEN** a parent attempts to cancel a fulfilled redemption
- **THEN** the attempt is refused, since the reward was already handed over; reverting it to pending first is the way to undo it

#### Scenario: Cancelled redemption cannot be revived

- **WHEN** any transition is attempted on a cancelled redemption
- **THEN** it is refused and the redemption stays cancelled

#### Scenario: Two parents resolve the same request at once

- **WHEN** two attempts to change the same pending redemption are submitted simultaneously
- **THEN** exactly one takes effect and the other is refused as already resolved, leaving a single consistent outcome

#### Scenario: Redemption no longer exists

- **WHEN** a transition names a redemption that is not in the caller's household
- **THEN** it is refused as not found

#### Scenario: Parent cancels with a note

- **WHEN** a parent cancels a pending redemption and supplies a note
- **THEN** the redemption is cancelled and the note is recorded on it

#### Scenario: Parent un-fulfils with a note

- **WHEN** a parent un-fulfils a redemption and supplies a note
- **THEN** the redemption returns to pending and the note is recorded on it

#### Scenario: Reversal without a note

- **WHEN** a parent cancels or un-fulfils a redemption without supplying a note
- **THEN** the transition succeeds and no note is recorded

#### Scenario: A later reversal replaces an earlier note

- **WHEN** a redemption that already carries a note from a previous reversal is reversed again with a new note
- **THEN** the redemption carries only the new note

## ADDED Requirements

### Requirement: The redeeming member is alerted when their redemption is reversed

The system SHALL indicate to the member who redeemed a reward when a parent cancels it or un-fulfils it, on that member's own device, and SHALL announce a given reversal once. It SHALL NOT announce the same reversal to the same device more than once, including across restarts of the app.

#### Scenario: A pending redemption is cancelled

- **WHEN** a parent cancels a member's pending redemption
- **THEN** that member is alerted, naming the reward, on their own device

#### Scenario: A fulfilled redemption is un-fulfilled

- **WHEN** a parent un-fulfils a member's redemption
- **THEN** that member is alerted, naming the reward, on their own device

#### Scenario: The reversal included a note

- **WHEN** a parent's reversal included a note
- **THEN** the alert includes that note

#### Scenario: The reversal had no note

- **WHEN** a parent's reversal did not include a note
- **THEN** the member is still alerted, without a note in it

#### Scenario: Data is re-read with nothing new

- **WHEN** the app re-reads its data and a reversal it already announced has not changed again
- **THEN** no new alert is raised

#### Scenario: Member returns after being away

- **WHEN** a member opens the app after one of their redemptions was reversed while it was closed
- **THEN** they are alerted about it if this device has not already announced it

#### Scenario: Permission is requested only when there is something to say

- **WHEN** a member has never had a redemption reversed
- **THEN** the app does not ask for permission to send notifications

#### Scenario: Permission is refused

- **WHEN** a member declines notification permission
- **THEN** their redemption history still shows the reversal and its note, and the app does not ask again on its own
