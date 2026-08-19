## MODIFIED Requirements

### Requirement: Redemptions form an append-only ledger

The system SHALL record each redemption as a permanent entry capturing the reward, its name, the points spent, who redeemed it, and when. Those facts SHALL NOT be modified after creation, and no entry SHALL be removed — including a cancelled one, which remains in the ledger marked as cancelled.

A redemption's fulfillment state, the record of which parent last changed it and when, and an optional note attached to its most recent reversal are the only parts of an entry that may change.

#### Scenario: Reward is repriced after redemption

- **WHEN** a reward's cost changes after it was redeemed
- **THEN** existing redemptions still show the points actually spent at the time

#### Scenario: Redemption is resolved

- **WHEN** a redemption is fulfilled, un-fulfilled, or cancelled
- **THEN** the reward, points spent, who redeemed it, and when are unchanged; only its state, the record of who resolved it, and its reversal note may differ

#### Scenario: Redemption is cancelled

- **WHEN** a redemption is cancelled
- **THEN** it remains in the ledger as a cancelled entry rather than disappearing from history

#### Scenario: A note is overwritten by a later reversal

- **WHEN** a redemption already carrying a reversal note is reversed again
- **THEN** the entry's reversal note reflects only the most recent reversal

### Requirement: Members see their own points; parents see everyone's

The system SHALL show a member their own balance and redemption history, and SHALL show parents the balance of each child in the household. Each redemption in a member's history SHALL carry its fulfillment state, so a request still awaiting a parent is distinguishable from a reward already received, and SHALL carry its reversal note when one was given.

#### Scenario: Child views the rewards screen

- **WHEN** a member holding the child role opens rewards
- **THEN** they see their own balance, the available rewards, and their own redemption history with each entry's state

#### Scenario: Child has an unfulfilled request

- **WHEN** a child has redeemed a reward that no parent has fulfilled yet
- **THEN** that entry is shown as still awaiting a parent, not as a reward already received

#### Scenario: Parent views the rewards screen

- **WHEN** a member holding the parent role opens rewards
- **THEN** they see each child's balance alongside the available rewards

#### Scenario: A reversed redemption carries its note

- **WHEN** a member views a redemption in their history that was cancelled or un-fulfilled with a note
- **THEN** the note is shown alongside that entry
