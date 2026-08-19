## Why

A parent can already cancel a pending redemption (refunding points) or un-fulfil one they resolved by mistake, but neither transition lets them explain why, and the child who owns the redemption is never told it happened — they only find out by reopening the app and noticing their balance or a status pill changed.

## What Changes

- `PATCH /redemptions/{redemptionId}` accepts an optional free-text note alongside the target `status`, recorded on the redemption when the target is `pending` (un-fulfil) or `cancelled` (cancel). Fulfilling does not take a note.
- The note is part of the redemption's durable record, not a one-shot message: it is returned with the redemption and shown on the owning member's history row for that entry, so it survives a missed or dismissed notification.
- The child whose redemption was reversed receives a local device notification (system banner + badge, mirroring the existing parent-facing pending-redemption alert) naming the reward and including the note when one was given. Each reversal is announced once per device, the same de-duplication rule the existing parent alert already follows.
- The child's device requests OS notification permission the first time it has a reversal to announce, and does not re-prompt after a refusal — same pattern as the parent side.
- Un-fulfilling, which today has no confirmation step at all, gains one (mirroring cancel's existing confirmation) so a parent has a deliberate moment to add a note before either reversal.

**Not changing**: the legal state transitions themselves (`pending → fulfilled`, `fulfilled → pending`, `pending → cancelled`), who may perform them (parents only), or the refund mechanics on cancel.

## Capabilities

### New Capabilities

None — this extends the existing redemption-fulfillment lifecycle and its record-keeping rather than introducing a new capability.

### Modified Capabilities

- `redemption-fulfillment`: un-fulfilling and cancelling accept an optional note, and a reversal (either transition) notifies the redeeming member on their own device once. **Note**: `openspec/specs/redemption-fulfillment/spec.md` does not exist yet — this capability was defined by `add-redemption-fulfillment-queue`, which is fully implemented (its `tasks.md` is complete bar one verification-run checkbox) but was never archived, so main specs never picked it up. This change's delta is written as a further modification on top of that change's still-pending delta, not against current main. See Impact.
- `rewards-and-points`: the "Redemptions form an append-only ledger" requirement gains the reversal note as another attribute that may be set when the entry is resolved (alongside the fulfillment state and who resolved it, per the same requirement as already modified by the pending `add-redemption-fulfillment-queue` delta).

## Impact

- **Backend**: `backend/cdk/lambda/rewards/update-redemption-status.ts` (parse and store the optional note on the `pending`/`cancelled` transitions), `backend/cdk/lambda/rewards/redemptions.ts` (`presentRedemption` returns it), DynamoDB redemption item (new attribute), `backend/cdk/scripts/verify-redemption-lifecycle.mjs` (extend to cover the note and, if practical from a script, the notification trigger conditions).
- **iOS**: `StarTime/Models/Redemption.swift`, `StarTime/Services/RewardService.swift` and `RewardStore.swift` (thread the optional note through `cancel`/`unfulfill`), `StarTime/Views/RewardsView.swift` (note entry on cancel's existing confirmation and on un-fulfil's new one; display the note on history rows), a new child-facing notifier alongside `StarTime/Services/PendingRedemptionNotifier.swift`, and its wiring into `StarTime/Views/MainTabView.swift`.
- **Process**: `add-redemption-fulfillment-queue` (implemented, unarchived) should be archived before or alongside this change so `openspec/specs/redemption-fulfillment/spec.md` and the `rewards-and-points` ledger wording actually exist in main when this change is archived — otherwise this change's delta has nothing in main to apply against.
- **Docs**: CLAUDE.md's redemption-lifecycle and notification sections gain the note field and the second (child-facing) notifier.
