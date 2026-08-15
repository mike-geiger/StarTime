## MODIFIED Requirements

### Requirement: A balance is points earned minus points spent

The system SHALL maintain each member's balance as the total points from their completions less the total from their redemptions that have not been cancelled. A cancelled redemption SHALL NOT count against the balance.

#### Scenario: Member completes a chore

- **WHEN** a chore worth some points is completed
- **THEN** that member's balance increases by exactly that amount

#### Scenario: Member redeems a reward

- **WHEN** a reward is redeemed
- **THEN** that member's balance decreases by exactly the reward's cost

#### Scenario: Redemption is cancelled

- **WHEN** a redemption is cancelled
- **THEN** the points it spent no longer count against that member's balance

#### Scenario: Member with no activity

- **WHEN** a member has completed nothing and redeemed nothing
- **THEN** their balance is zero

### Requirement: Redemptions form an append-only ledger

The system SHALL record each redemption as a permanent entry capturing the reward, its name, the points spent, who redeemed it, and when. Those facts SHALL NOT be modified after creation, and no entry SHALL be removed — including a cancelled one, which remains in the ledger marked as cancelled.

A redemption's fulfillment state, and the record of which parent last changed it and when, are the only parts of an entry that may change.

#### Scenario: Reward is repriced after redemption

- **WHEN** a reward's cost changes after it was redeemed
- **THEN** existing redemptions still show the points actually spent at the time

#### Scenario: Redemption is resolved

- **WHEN** a redemption is fulfilled, un-fulfilled, or cancelled
- **THEN** the reward, points spent, who redeemed it, and when are unchanged; only its state and the record of who resolved it differ

#### Scenario: Redemption is cancelled

- **WHEN** a redemption is cancelled
- **THEN** it remains in the ledger as a cancelled entry rather than disappearing from history

### Requirement: Members see their own points; parents see everyone's

The system SHALL show a member their own balance and redemption history, and SHALL show parents the balance of each child in the household. Each redemption in a member's history SHALL carry its fulfillment state, so a request still awaiting a parent is distinguishable from a reward already received.

#### Scenario: Child views the rewards screen

- **WHEN** a member holding the child role opens rewards
- **THEN** they see their own balance, the available rewards, and their own redemption history with each entry's state

#### Scenario: Child has an unfulfilled request

- **WHEN** a child has redeemed a reward that no parent has fulfilled yet
- **THEN** that entry is shown as still awaiting a parent, not as a reward already received

#### Scenario: Parent views the rewards screen

- **WHEN** a member holding the parent role opens rewards
- **THEN** they see each child's balance alongside the available rewards
