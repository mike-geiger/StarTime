## Why

Redeeming a reward today is a single instant: points leave the child's balance, a ledger entry appears, and nothing else happens. But the reward itself — the ice cream, the extra screen time, the trip to the park — is delivered by a parent in the real world, later. The app records that a child *paid*, and then forgets about it. Nothing tells a parent that someone is waiting on them, and nothing records whether the reward was ever actually handed over.

A redemption is a promise, not a completed transaction. It needs to stay visible until a parent says it was kept.

## What Changes

- **A redemption now has a fulfillment state**: `pending` when a child redeems, `fulfilled` once a parent hands the reward over, `cancelled` if the request is called off. Redeeming still debits points immediately, so a child cannot queue up more than they can afford.
- **Parents get a queue.** Pending redemptions across the whole household appear in a "Waiting on you" section at the top of the parent's Rewards screen, with the child's name, the reward, and when it was requested.
- **Parents can mark a redemption fulfilled**, revert an accidental fulfillment back to pending, or cancel a pending request — which refunds the points in the same atomic write that cancels it, so a balance can never drift from its ledger.
- **Only parents can change a redemption's state.** Enforced server-side, not by hiding buttons.
- **Parents are notified when redemptions are waiting**: a badge on the Rewards tab, an app icon badge, and a local notification for pending requests the device has not already announced. Notification permission is requested the first time a parent actually has something waiting, never at launch.
- **Children see the state of their own requests** — a pending request reads as awaiting a parent rather than as already delivered.
- **Existing redemptions are treated as fulfilled.** Every redemption recorded before this change was, under the old model, complete the moment it was made. They must not appear in a parent's queue as a backlog of imaginary obligations.
- **No change to how points are spent or checked.** The conditional balance decrement that makes redemption atomic and race-proof stays exactly as it is.

### Non-goals

- **Push notifications to a closed app.** A local notification can only be posted by a running app, so a parent whose app is fully closed learns about a pending redemption the next time they open it. Remote push (APNs) is a deliberate follow-up, not part of this change.
- **Partial or negotiated fulfillment.** A redemption is fulfilled or it is not; there is no "half delivered" state.
- **Notifying children when their reward is fulfilled.** Only the parent-facing alert is in scope.

## Capabilities

### New Capabilities

- `redemption-fulfillment`: The lifecycle of a redemption after the points are spent — its states and the transitions between them, who may perform them, how cancellation returns points, and how a parent is made aware that requests are waiting.

### Modified Capabilities

- `rewards-and-points`: Three existing requirements no longer describe the system accurately once redemptions can be cancelled and can carry state.
  - *"Redemptions form an append-only ledger"* — the facts of a redemption stay immutable, but its fulfillment state is now mutable by design.
  - *"A balance is points earned minus points spent"* — a cancelled redemption returns its points, so it no longer counts against the balance.
  - *"Members see their own points; parents see everyone's"* — what each role sees now includes fulfillment state and, for parents, the pending queue.

## Impact

**Backend** (`backend/cdk/`)

- `lambda/rewards/redeem-reward.ts` — writes `status: 'pending'` on the new redemption. The balance transaction is untouched.
- `lambda/rewards/list-redemptions.ts` — normalizes a missing `status` to `fulfilled` on read, so legacy rows are handled in exactly one place and every client sees a definite state.
- `lambda/rewards/update-redemption-status.ts` — **new.** `PATCH /redemptions/{redemptionId}`; parent-only; applies one transition per call under a condition on the current state.
- `lambda/common/auth.ts` — a shared parent-role check, currently inlined in `generate-invite-code.ts`.
- `lib/api-stack.ts` — one new route and Lambda.
- Realtime needs no change: `REDEMPTION#` and `BALANCE#` already map to the `redemptions` and `balances` invalidation resources, so state changes and refunds propagate through the existing fan-out.
- DynamoDB needs no schema or index change — new attributes on an existing item shape.

**iOS**

- `Models/Redemption.swift` — a `RedemptionStatus` enum and the fulfillment audit fields.
- `Services/RewardService.swift` — the `PATCH` call and its 403/409 error mapping.
- `Services/RewardStore.swift` — pending-redemption derivation and the three transition actions.
- `Views/RewardsView.swift` — the parent queue section, the transition affordances, and status on a child's own rows.
- `Views/MainTabView.swift` — the Rewards tab badge.
- `Services/PendingRedemptionNotifier.swift` — **new.** Local notification scheduling, permission, and per-redemption deduplication.
- `SupportingFiles/Info.plist` — no new capability required; local notifications need no entitlement.

**Tests**

- `backend/cdk/scripts/verify-redemption-lifecycle.mjs` — **new.** Covers the full state machine, the refund, parent-only authorization, and concurrent transitions. Two identities are required, which the single-client XCUITest suite cannot provide.
- `StarTimeUITests.swift` — a parent redeeming on a child's behalf, seeing the queue, and fulfilling it.
