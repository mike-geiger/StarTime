## Context

See proposal.md - Why. Relevant current state:

- `PATCH /redemptions/{redemptionId}` (`backend/cdk/lambda/rewards/update-redemption-status.ts`) reads only `{ status }` from the body and applies one of three conditional transitions. Cancel already stamps `cancelledAt`/`cancelledByUID`; un-fulfil removes the `fulfilled*` attributes and sets `status: 'pending'` but stamps nothing of its own.
- The only existing notification pattern (`PendingRedemptionNotifier`) is parent-scoped: it observes `RewardStore.$redemptions` for the whole household, diffs against a `UserDefaults`-persisted announced-id set, and posts one local notification per newly pending redemption. It never calls `refresh()` on the store it observes.
- Cancel's parent-facing confirmation is a plain two-button `.confirmationDialog` (`RewardsView.swift`); un-fulfil has no confirmation at all. `.confirmationDialog` cannot host a `TextField`.

## Goals / Non-Goals

**Goals:**
- Let a parent attach a short optional note to a cancel or an un-fulfil, stored durably on the redemption.
- Alert the member who redeemed — on their own device — exactly once per reversal, including un-fulfils that recur on the same redemption.
- Reuse the existing parent-side notifier's shape (local notification, lazy permission request, no-refetch rule) rather than inventing a new pattern.

**Non-Goals:**
- Attributing a reversal to the specific parent who performed it in the notification body or in the Swift model (the spec requires naming the reward, not the actor; `cancelledByUID`/a symmetric un-fulfil actor field already exist or can be added server-side if needed later, but nothing client-facing depends on it here).
- Any change to who may perform a transition, which transitions are legal, or refund mechanics — untouched.
- A push/APNs path for a backgrounded child device — out of reach for the same reason the parent side doesn't have one (CLAUDE.md: a sleeping device's socket is dead and there's no queue).

## Decisions

**Single `reversalNote` field, overwritten each reversal, cleared on fulfil.** One attribute on the redemption item (not separate cancel/un-fulfil fields) because only the *most recent* reversal's note is ever meaningful to show — an older note from a corrected mistake would be confusing to leave attached to a since-resolved item. Fulfilling clears it, since fulfil already resolves whatever the note was explaining. Alternative considered: leave the note untouched on fulfil so history retains "why it was un-fulfilled that one time" — rejected because the display requirement is about the redemption's *current* state, not an audit trail, and a stale note on a now-fulfilled reward reads as a live explanation for something no longer true.

**New `unfulfilledAt` timestamp, for dedup only.** Cancel is terminal, so `cancelledAt` is already a stable one-time marker the notifier can key off. Un-fulfil is not terminal — the same redemption can be fulfilled, un-fulfilled, fulfilled, and un-fulfilled again — so a bare redemption id can't tell the notifier "this is a new reversal" the way it can for the parent-side pending queue. `unfulfilledAt` gives each un-fulfil its own timestamp to dedup against, mirroring how `fulfilledAt`/`cancelledAt` already work. It rides in the API response and the Swift model alongside `reversalNote`.

**Dedup key is `(redemptionId, cancelledAt ?? unfulfilledAt)`, not bare id.** The existing parent notifier's announced-set only needs bare ids because "pending" only ever happens once per redemption from its perspective (creation). Here the same id can need a fresh announcement more than once, so the persisted `UserDefaults` set (new key, e.g. `announcedReversedRedemptions.<householdId>`) stores composite strings instead of ids alone.

**Note entry via `.alert` with an embedded `TextField`, not a `.sheet`.** `.confirmationDialog` cannot host a `TextField`, but SwiftUI's `.alert(_:isPresented:actions:)` can embed one in its `actions` closure (the same pattern apps use for "rename" prompts). This keeps the interaction as lightweight as the existing plain confirmation — one tap, no navigation — for what's meant to be a short explanation. A `.sheet` was considered and rejected as disproportionate ceremony for a one-line optional note; it would also require its own dismissal/cancel affordance the alert gets for free. Un-fulfil, which has no confirmation today, gets the same alert shape for consistency, addressing the proposal's point that un-fulfil currently has no deliberate moment before it fires.

**New notifier filters to the signed-in member's own redemptions, not household-wide.** `PendingRedemptionNotifier` deliberately shows parents every pending redemption in the household. The reversal notifier must do the opposite: alert only the member whose own redemption changed, so filtering is `redemption.redeemedByUID == current uid`, not a role check. This also means the notifier isn't gated to "child role" — it fires for whichever member redeemed, matching the spec's "redeeming member" framing rather than hardcoding a role that the data model doesn't otherwise enforce at the redemption level.

**Note length is capped at 500 characters, enforced server-side.** Arbitrary but generous for a short explanation; guards against unbounded growth of a DynamoDB item under the existing per-item size ceiling, and against a redemption's history display taking arbitrary space. Rejected an unlimited note as unnecessary risk for no real benefit at this size of app.

**A note supplied on a `fulfilled` target is not an error — it's ignored.** Consistent with how the handler already reads only the fields relevant to the transition it's applying. Rejected returning 400 for a note alongside `status: 'fulfilled'`: the client-side UI simply never offers a note field for that transition, so this can only happen from a hand-crafted request, and refusing it protects nothing a legitimate client needs.

## Risks / Trade-offs

- [A child's device backgrounded or asleep never sees the local notification, only the in-app history once reopened] → Mitigation: the note is part of the durable record per the `rewards-and-points` delta, not just the notification payload, so the explanation isn't lost even when the alert itself never fires — this is why the note lives on the redemption rather than only in a transient push.
- [Same account signed in on two child devices could each announce the same reversal independently] → Not a new problem: the existing parent-side notifier has identical per-device dedup semantics already; this change doesn't make it worse.
- [`.alert` with an embedded `TextField` has less room and no multi-line growth compared to a custom sheet] → Acceptable: the note is meant to be a short explanation, not a message thread.

## Migration Plan

Both new attributes (`reversalNote`, `unfulfilledAt`) are purely additive on an existing item shape — no backfill, no index change, no new access pattern. Missing on old items reads the same way missing `status` already does elsewhere: absence just means "never happened." Deploy backend first (old clients that never send `note` are unaffected); ship the iOS release after. Rollback is a plain revert of the Lambda and app code — nothing destructive to undo.

**Sequencing with `add-redemption-fulfillment-queue`:** as noted in proposal.md - Impact, that change is implemented but unarchived, and this change's specs are written as a further modification on top of its still-pending delta. Archive `add-redemption-fulfillment-queue` before or alongside this change so `redemption-fulfillment` and the fulfillment-aware `rewards-and-points` wording actually land in main specs.
