# Rewards and Points Specification

## Purpose

The payoff side of the app: rewards parents offer, the point balance each child accrues from completed chores, and redeeming points for a reward.

## Requirements

### Requirement: Parents define rewards with a point cost

The system SHALL let parents create, edit, and delete rewards, each with a name, icon, and point cost.

#### Scenario: Parent creates a reward

- **WHEN** a parent supplies a name, icon, and point cost
- **THEN** the reward is saved to the household and becomes available to redeem

#### Scenario: Parent deletes a reward

- **WHEN** a parent deletes a reward
- **THEN** it stops appearing as redeemable, while redemptions already recorded against it remain in history

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

### Requirement: Balances never drift from the ledger

The system SHALL update a balance in the same atomic operation as the completion or redemption that justifies it, so the two can never disagree.

#### Scenario: Recording a completion fails partway

- **WHEN** a completion cannot be fully recorded
- **THEN** neither the completion nor the balance change is applied

#### Scenario: Balance is recomputed from history

- **WHEN** a member's stored balance is compared against their completions minus redemptions
- **THEN** the two agree

### Requirement: Redemption is refused when points are insufficient

The system SHALL verify sufficient balance as part of the redemption itself, such that the check and the deduction cannot be separated. A redemption that would overdraw SHALL be refused with an explanation.

Checking the balance and then deducting as two steps can be defeated by two redemptions racing: both read a sufficient balance, and both proceed.

#### Scenario: Member has enough points

- **WHEN** a member redeems a reward they can afford
- **THEN** the redemption is recorded and their balance decreases by the cost

#### Scenario: Member lacks enough points

- **WHEN** a member attempts to redeem a reward costing more than their balance
- **THEN** the redemption is refused, they are told they do not have enough points, and their balance is unchanged

#### Scenario: Two redemptions race for the same points

- **WHEN** two redemptions are submitted at once and the balance covers only one
- **THEN** exactly one succeeds and the other is refused, leaving the balance non-negative

#### Scenario: Cost is taken from the stored reward

- **WHEN** a redemption is submitted
- **THEN** the points deducted come from the reward as stored, never from a cost supplied by the caller

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
