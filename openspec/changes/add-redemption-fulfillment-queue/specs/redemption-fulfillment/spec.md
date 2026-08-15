## Purpose

What happens to a redemption after the points are spent. A reward is handed over by a parent in the real world, some time after a child asks for it, so a redemption stays an open promise until a parent confirms it was kept — and parents need to be told when promises are waiting on them.

## ADDED Requirements

### Requirement: A redemption stays pending until a parent resolves it

The system SHALL record every new redemption as pending, and SHALL keep it pending until a parent marks it fulfilled or cancels it. The points SHALL be deducted when the redemption is made, not when it is fulfilled, so that a member cannot have more pending redemptions than their balance covers.

Deducting at fulfillment would let a member queue several requests they collectively cannot afford, and would move the point of failure to the parent, who would tap "fulfilled" and be told there were never enough points.

#### Scenario: Member redeems a reward

- **WHEN** a member redeems a reward they can afford
- **THEN** the redemption is recorded as pending, and their balance decreases by the reward's cost immediately

#### Scenario: Member redeems twice in a row

- **WHEN** a member redeems two rewards whose combined cost exceeds their balance
- **THEN** the second redemption is refused for insufficient points, because the first already debited them

#### Scenario: Pending redemption is not yet delivered

- **WHEN** a redemption is pending
- **THEN** it is presented as awaiting a parent rather than as a reward already received

### Requirement: Only parents may change a redemption's fulfillment state

The system SHALL restrict fulfilling, un-fulfilling, and cancelling to members holding the parent role in the household that owns the redemption, and SHALL enforce this independently of what any interface offers.

#### Scenario: Parent resolves a redemption

- **WHEN** a member holding the parent role changes the state of a redemption in their own household
- **THEN** the change is applied

#### Scenario: Child attempts to resolve a redemption

- **WHEN** a member holding the child role attempts to change any redemption's state, including one of their own
- **THEN** the attempt is refused and the redemption is left unchanged

#### Scenario: Redemption belongs to another household

- **WHEN** a parent attempts to change the state of a redemption that is not in their own household
- **THEN** the attempt is refused, and no information about that redemption is disclosed

### Requirement: Fulfillment state changes only along defined transitions

The system SHALL permit a redemption to move from pending to fulfilled, from fulfilled back to pending, and from pending to cancelled. Every other transition SHALL be refused, and cancelled SHALL be final. A transition SHALL be applied only if the redemption is still in the state the transition starts from.

Requiring the starting state is what makes concurrent attempts safe: two parents resolving the same request at the same moment must not both take effect, particularly when one of them is a cancellation that returns points.

#### Scenario: Parent marks a pending redemption fulfilled

- **WHEN** a parent fulfills a pending redemption
- **THEN** it becomes fulfilled, recording which parent resolved it and when

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

### Requirement: Cancelling a redemption returns the points that were spent

The system SHALL return the points to the member who redeemed, in the same atomic operation that marks the redemption cancelled, so the balance and the ledger can never disagree. The amount returned SHALL be the points recorded on the redemption itself, never an amount supplied by the caller or re-read from the reward.

Re-reading the reward would refund whatever it costs today, which is not necessarily what was paid; the reward may have been repriced or deleted since.

#### Scenario: Cancellation returns points

- **WHEN** a parent cancels a pending redemption
- **THEN** the redeeming member's balance increases by exactly the points that redemption recorded as spent

#### Scenario: Cancellation cannot be half-applied

- **WHEN** a cancellation cannot be fully applied
- **THEN** neither the state change nor the refund takes effect

#### Scenario: Reward was repriced after redemption

- **WHEN** a redemption is cancelled after its reward's cost changed
- **THEN** the points returned are the points originally spent, not the current cost

#### Scenario: Reward was deleted after redemption

- **WHEN** a redemption is cancelled after its reward was deleted
- **THEN** the cancellation still succeeds and the original points are returned

#### Scenario: Fulfilling does not move points

- **WHEN** a redemption is fulfilled or un-fulfilled
- **THEN** no balance changes, because the points were already spent when it was redeemed

### Requirement: Redemptions predating fulfillment tracking count as fulfilled

The system SHALL treat a redemption recorded without a fulfillment state as fulfilled.

Under the previous behavior a redemption was complete the moment it was made. Treating those as pending would confront every existing family with a queue of obligations they already met, and no parent could tell the real requests from the historical ones.

#### Scenario: Historical redemption is read

- **WHEN** a redemption recorded before fulfillment tracking existed is read
- **THEN** it reports as fulfilled

#### Scenario: Historical redemption and the queue

- **WHEN** a parent views the requests waiting on them
- **THEN** redemptions predating fulfillment tracking are absent from it

### Requirement: Parents see every request waiting on them in one place

The system SHALL show parents all pending redemptions in their household together, identifying for each the member who redeemed, the reward, the points spent, and when it was requested. The longest-waiting request SHALL appear first.

#### Scenario: Requests are waiting

- **WHEN** a parent opens rewards and pending redemptions exist
- **THEN** they are listed together, ahead of the rest of the screen, oldest request first

#### Scenario: Nothing is waiting

- **WHEN** no redemptions are pending
- **THEN** no queue is shown

#### Scenario: A request arrives while a parent is looking

- **WHEN** a child redeems a reward while a parent's device is open to the household
- **THEN** the request appears in that parent's queue without the parent refreshing

#### Scenario: A request is resolved on another device

- **WHEN** one parent fulfills a request while another parent's device is open
- **THEN** it leaves the second parent's queue without them refreshing

#### Scenario: Child views rewards

- **WHEN** a member holding the child role opens rewards
- **THEN** they are not shown the household's pending queue, only the state of their own requests

### Requirement: Parents are alerted that redemptions are waiting

The system SHALL indicate to a parent how many redemptions are pending, without the parent having to open the rewards screen, and SHALL announce a newly pending redemption once. It SHALL NOT announce the same redemption to the same device more than once, including across restarts of the app, and SHALL NOT alert members holding the child role.

Repeating the announcement on every re-read would make it constant noise, since the app re-reads its data routinely.

#### Scenario: A count of what is waiting

- **WHEN** a parent has pending redemptions
- **THEN** the count is visible from anywhere in the app, without opening rewards

#### Scenario: The last request is resolved

- **WHEN** the final pending redemption is fulfilled or cancelled
- **THEN** the indicated count returns to none

#### Scenario: A new request arrives

- **WHEN** a redemption becomes pending and the parent's device has not announced it before
- **THEN** the parent is alerted, identifying who is asking for what

#### Scenario: Data is re-read with nothing new

- **WHEN** the app re-reads its data and the pending redemptions are ones this device already announced
- **THEN** no new alert is raised

#### Scenario: Parent returns after being away

- **WHEN** a parent opens the app after redemptions became pending while it was closed
- **THEN** they are alerted about the ones this device has not already announced

#### Scenario: Child's device

- **WHEN** the signed-in member holds the child role
- **THEN** no pending-redemption alert is raised on that device, whatever is pending in the household

#### Scenario: Permission is requested only when there is something to say

- **WHEN** a parent has never had a pending redemption
- **THEN** the app does not ask for permission to send notifications

#### Scenario: Permission is refused

- **WHEN** a parent declines notification permission
- **THEN** the pending queue and its count remain fully available, and the app does not ask again on its own
