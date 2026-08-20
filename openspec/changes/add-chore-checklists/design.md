## Context

Today a chore completes in one request: `record-completion.ts` runs a single `TransactWriteItems` that writes the `ChoreCompletion`, credits the balance, and claims a `COMPLETEDON#{choreId}#{scheduledDate}` marker under `attribute_not_exists(PK)` — that marker is the *only* guard, and it's what makes "one completion per chore per day" safe under concurrent taps.

A checklist chore replaces that one request with several, spread over the day, each touching one item — and the credit still has to fire exactly once, atomically, on whichever tap happens to close the set. See proposal.md for why (the "Morning Chores" case) and what's in scope (items as pure gates, no per-item points, uncheck-with-clawback by any household member, edits never retroactive).

## Goals / Non-Goals

**Goals:**
- Reuse the existing `COMPLETEDON#` marker as the single source of truth for "is this chore done today," rather than inventing a second notion of done-ness derived from checked-item counting.
- Make the common case (checking an item that doesn't close the set) a single cheap write, not a transaction.
- Make the race around "who closes the set" and "who claims a reversal" provably safe without a retry loop.

**Non-Goals:**
- Per-item point values or partial credit — explicitly ruled out in the proposal.
- Restricting check/uncheck to the assignee or to parents — see Decisions below on why this isn't a new permission to design.
- Snapshotting the required item list per day for historical display fidelity (e.g. "you had 3 items that day, now the chore only has 2") — the proposal only commits to completion/incompletion itself being stable, not the display of what was required; deferred.

## Decisions

### The checklist-progress item, and why it's separate from `ChoreCompletion`

A new item: `PK=HOUSEHOLD#{id}`, `SK=CHECKLIST#{choreId}#{scheduledDate}`, holding `choreId`, `scheduledDate`, and `checkedItemIds` as a native DynamoDB String Set. It records *progress*, not *completion* — completion is still, exclusively, "does a non-reversed `ChoreCompletion` exist for this chore and day," unchanged from today. This separation is what makes edits to the item list non-retroactive for free: nothing ever recomputes a past day's completion by comparing old checked-items against a current item list, because completion was decided once, at write time, and is never revisited.

### Checking an item is two independent writes, not one transaction

1. **Unconditional `ADD checkedItemIds :itemId`** on the checklist-progress item (creating it if absent). Cheap, idempotent, always succeeds — a double-tap or a lost race here has no bad outcome, since sets absorb duplicates.
2. A **strongly consistent re-read** of the checklist-progress item, compared against the chore's current `items` (also freshly read — never trust the client's idea of what's required). If the checked set now covers every required item **and** no `COMPLETEDON#` marker exists yet, attempt the same four-part closing transaction `record-completion.ts` already does (`ChoreCompletion` + balance credit + `COMPLETEDON#` `Put` under `attribute_not_exists`). If that transaction is cancelled — someone else's tap already claimed it — swallow it as a no-op, not an error.

Splitting these matters because of a real race: if two different items are each other's last missing piece and get checked at the same moment, neither request's own write locally looks complete from a "read current, decide, write" perspective — a naive implementation can drop the credit entirely, with both items ending up checked but nothing ever firing. Requiring the re-read to be *strongly consistent* and to happen *after* the item's own write commits is what closes that gap: DynamoDB serializes writes to a single item, so whichever of the two requests' writes lands second is guaranteed, by the time it does its own post-write read, to observe the other's already-landed contribution too — that request's re-read sees the full set and wins the closing transaction. The earlier request's re-read correctly does not see completion, because at that instant the set genuinely wasn't complete yet. No retry loop is needed; the existing `attribute_not_exists` marker condition remains the single authoritative tie-breaker if both requests' re-reads somehow do see a complete set at once.

**Alternative considered**: read-then-decide entirely client-side-to-the-request (read current progress once, compute completion, transact) without the intermediate unconditional write. Rejected — it has exactly the dropped-credit race above, and retrying it correctly requires the same "write first, then re-read" shape anyway, just with extra steps.

### Unchecking mirrors checking, symmetrically

1. **Unconditional `DELETE checkedItemIds :itemId`.** Always succeeds.
2. If a `COMPLETEDON#` marker exists for that day (i.e. the chore was already complete), attempt a reversal transaction: mark the `ChoreCompletion` reversed, debit the balance, delete the marker. Gate it on `attribute_not_exists(reversedAt)` on the completion record — the same role the `pending`/`fulfilled` status guard plays for redemption transitions. If two people uncheck two different items on an already-complete checklist at once, both attempt this transaction; exactly one's condition holds, the other is swallowed as "already reversed." The checked-set removal itself (step 1) already succeeded independently for both, so no user-visible action is lost.

The debit uses `pointsAwarded` as recorded on the `ChoreCompletion` itself, never the chore's current point value — same reasoning as redemption cancellation not re-reading the reward's current cost. It is **not** conditioned on the resulting balance staying non-negative; the proposal commits to that explicitly.

To find the `ChoreCompletion` to reverse without a range query, `Keys.completionMarker` gains a `completedAt` field (it already stores `completionId`) — `completedAt` + `completionId` + `choreId` reconstructs the completion's exact `SK` (`COMPLETION#{completedAt}#{completionId}`), so the reversal path does a direct `GetItem`/`Update` by key instead of scanning a date range.

### The explicit "Mark Complete" action is the same closing step, without a preceding item write

When an edit to the item list leaves an already-fully-checked set satisfying the new (shorter) requirement, there's no unchecked item left to tap — so this needs its own endpoint that just re-runs step 2 of "checking an item" (re-read, compare, attempt the closing transaction) without step 1. It fails harmlessly (not-yet-satisfied) if called when the set genuinely isn't complete.

### Authorization: no new role check

`record-completion.ts` today takes `completedByUID` from the request body and applies it unvalidated against the caller's role — any authenticated household member can already complete any chore assigned to anyone. Checklist check/uncheck/mark-complete/reversal follow that same existing precedent rather than introducing a new restriction: any household member may act, and points are always credited to `chore.assignedToUID`, never to whoever tapped. "Either child or parent can uncheck" is this existing behavior extended to a new action, not a new grant.

### Realtime and cascade delete

- `stream-fanout.ts`'s `resourceFor` gains `if (sortKey.startsWith('CHECKLIST#')) return 'chores';` — checklist progress rides the same `chores` invalidation `ChoreStore` already subscribes to; no client-side invalidation-handling changes needed.
- `delete-account.ts`'s cascade-delete prefix list gains `'CHECKLIST#'`, alongside `'COMPLETEDON#'` — same reasoning: it lives under the household PK, outside every other prefix's range, and would otherwise orphan on account deletion.

### `ChoreCompletion`'s "append-only" requirement gets a named exception

The current `chore-tracking` spec states completion entries are never modified after creation. Reversal fields (`reversedAt`/`reversedByUID`/`reversalNote`) genuinely violate that. The spec delta modifies this requirement rather than leaving it contradicted — see specs.

## Risks / Trade-offs

- **Any household member can reverse any completion, including a sibling's or a parent's own past credit** → Accepted deliberately (matches existing completion permissiveness; the alternative is a new restriction nothing else in this app has). If abuse turns out to matter in practice, narrowing to assignee-or-parent is a backward-compatible follow-up.
- **Balance can go negative from a clawback** → Accepted per proposal; no floor, no cap. Purely a display concern for later, not a correctness one — the ledger stays exactly accurate.
- **Two separate writes (item toggle, then conditional transaction) instead of one** → A window exists where `checkedItemIds` shows fully-checked but the completion transaction hasn't landed yet. Harmless: nothing infers completion from the checked set, only from the `ChoreCompletion`'s existence, so this window is invisible to every other invariant (streaks, `isCompletedToday`).

## Migration Plan

Purely additive — no backfill. Existing chores carry no `items` field, which reads as an empty checklist (i.e., today's single-tap chore), so behavior for every existing chore is unchanged the moment this deploys. Existing `ChoreCompletion` records have no `reversedAt`, which reads as not-reversed — exactly the same "absence defaults to the pre-feature meaning" pattern already used for `Redemption.status`. No forward migration script, no `verify-migration-shape.mjs` extension needed. Rollback is a plain revert; any `CHECKLIST#` items left behind are inert (nothing but this feature ever reads them).
