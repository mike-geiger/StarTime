## Why

Some chores aren't one action — "Morning Chores" is really brush teeth + eat breakfast + practice piano — and today a chore can only be marked done as a single tap. A parent currently has to either split it into several separate point-earning chores (paying out per sub-task, which isn't what they want) or trust one tap that nothing was actually done item-by-item.

## What Changes

- `Chore` gains an optional list of checklist items (id + title). A chore with items is a checklist chore; a chore with none behaves exactly as it does today — existing chores are unaffected.
- For a checklist chore, completion is no longer one request: each item is checked independently, and the chore's points are credited only once every item is checked, in a single atomic transaction fired by whichever check closes the set — the same one-completion-per-day guard as today, reached by a different path.
- Items can be unchecked by either the assigned child or a parent, at any time — including after the chore has already completed for the day, so a fat-fingered check doesn't require a parent to fix. Unchecking a completed chore reverses it: the recorded completion is marked reversed (not deleted), the points are debited back off the member's balance — the debit is always the full amount originally credited, never capped, so the balance can go negative if those points were already spent — and the chore becomes completable again once every item is re-checked.
- Editing a chore's item list never retroactively completes or un-completes a day, past or current. If an edit leaves today's already-checked items covering every required item, the chore does not auto-complete — the assignee or a parent gets an explicit action to complete it, so every completion still comes from a deliberate tap, never a side effect of editing.
- Reversing a completed checklist chore accepts an optional note, the same shape as the existing redemption-reversal note, and the chore's own assignee is alerted on their device when it happens, naming the chore and including the note when one was given — the completion-side counterpart to the existing redemption-reversal alert.
- **BREAKING**: none. Existing chores carry an empty item list and are indistinguishable from today's single-tap chores in every respect.

## Capabilities

### New Capabilities

None — checklist items are a variant of how an existing chore is defined and completed, not a new kind of thing being tracked.

### Modified Capabilities

- `chore-tracking`: chores may carry checklist items; completion, the once-per-day guard, streaks, and history all account for per-item progress and for a completion that has since been reversed; a new alert notifies a chore's assignee when their own completion is reversed.

## Impact

- **Backend**: new DynamoDB item for per-day checklist progress (`PK=HOUSEHOLD#{id} SK=CHECKLIST#{choreId}#{scheduledDate}`); `backend/cdk/lambda/chores/save-chore.ts` (accept/validate items); `backend/cdk/lambda/chores/record-completion.ts` plus a new item check/uncheck handler (transactional credit on close, transactional debit on reversal, optimistic concurrency for "which tap closes the set"); the `ChoreCompletion` item gains `reversedAt`/`reversedByUID`/`reversalNote`; `DELETE /account` cascade delete and the realtime invalidation fan-out both need to know about the new item type; a new `backend/cdk/scripts/verify-checklist-completion.mjs` (concurrent last-item taps resolve to exactly one credit; reversal after the points are spent goes negative; an edited item list never retroactively flips a past or in-progress day).
- **iOS**: `StarTime/Models/Chore.swift` (items) and `StarTime/Models/ChoreCompletion.swift` (reversal fields); `ChoreService`/`ChoreStore` (per-item check/uncheck, the explicit complete action, `isCompletedToday`/`streak` filtering out reversed completions); `AddEditChoreView` (item list editor); `ChoresView` (per-item checkboxes, progress, the explicit "Mark Complete" affordance); a new `ChoreCompletionReversalNotifier` alongside `RewardReversalNotifier`, wired into `MainTabView`.
- **Docs**: CLAUDE.md's chore/completion sections gain the checklist model, the reversal/clawback rule, and the third notifier.
