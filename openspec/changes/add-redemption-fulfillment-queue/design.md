## Context

See proposal.md — Why.

The constraints that shape this design are all pre-existing:

- **A redemption's sort key is `REDEMPTION#{redeemedAtISO}#{id}`.** The timestamp sits between the prefix and the id, so the key cannot be reconstructed from a redemption id alone. Every existing read of redemptions is a range query, never a point read.
- **Balances are a denormalized counter** kept in the same `TransactWriteItems` as the ledger entry that justifies them. `redeem-reward.ts` already relies on a `ConditionExpression: balance >= :cost` to make the check and the deduction inseparable. Anything that returns points has to hold the same line.
- **Authorization lives in Lambda code.** A parent check already exists, inlined in `generate-invite-code.ts`, reading the household `METADATA` item's member map.
- **Realtime is invalidation-only.** `stream-fanout.ts` maps a changed item's sort-key prefix to a resource name; `REDEMPTION#` → `redemptions` and `BALANCE#` → `balances` are already wired.
- **There is real family data in `prod`.** Redemptions recorded before this change carry no fulfillment state.
- **The iOS stores are refetch-based and shared.** `RewardStore` is a single `@StateObject` on `MainTabView`, and CLAUDE.md records two bugs worth not repeating: refetching in response to a `@Published` change of an observed store spins the app forever, and clearing the realtime subscription in `stop()` silently kills the whole realtime layer.

## Goals / Non-Goals

**Goals:**

- Add the lifecycle without touching the atomic redemption path that already works.
- One place, server-side, where a missing fulfillment state gets its default — so no client ever has to know that legacy rows exist.
- Make an invalid or repeated transition a refusal from the write itself, not from a read-then-write.
- No new DynamoDB item shapes, no new index, no data backfill.

**Non-Goals:**

- Reworking how redemptions are queried. The range-scan read pattern stays.
- A general-purpose state machine. Three states and three transitions, hardcoded.
- Any change to `stream-fanout.ts`, the WebSocket layer, or the stores' invalidation wiring.

## Decisions

### Fulfillment state is an attribute on the existing redemption item

`status` (`pending` | `fulfilled` | `cancelled`), plus `fulfilledAt` / `fulfilledByUID` / `fulfilledByName` and `cancelledAt` / `cancelledByUID`, written onto the item already at `REDEMPTION#{redeemedAtISO}#{id}`.

*Alternative — a separate `PENDING#{id}` item to make the queue a cheap `begins_with` query.* Rejected: it makes the queue a second source of truth that has to be created, deleted, and kept transactionally consistent with the redemption on every transition, and it invites exactly the balance-drift class of bug the existing invariants exist to prevent. A household's pending list is a handful of items; filtering the redemption range for them is free at this scale.

Because the queue is derived by filtering, not by a dedicated query, the sort-key layout is unchanged and cascade delete in `delete-account.ts` needs no new case.

### A redemption is located by querying the range and matching on `id`

`PATCH /redemptions/{redemptionId}` cannot build a `Key` from the path parameter, because the sort key embeds `redeemedAt`. The handler queries `SK BETWEEN 'REDEMPTION#' AND 'REDEMPTION#~'` under the caller's own household PK and picks the item whose `id` matches, then issues the conditional write against that item's real key.

*Alternative — have the client send `redeemedAt` alongside the id.* Rejected on convention: handlers re-derive keys server-side and never trust client-supplied identifiers. It would also mean a client with a stale copy of a redemption could aim a write at a key that no longer exists and get a confusing not-found instead of a stale-state refusal.

*Alternative — a GSI keyed by redemption id.* Rejected as premature: a whole index to avoid a range query over a family's redemption history, on a path a parent hits a few times a day. If history ever grows enough to matter, an index keyed on `HOUSEHOLD#{id}` / `PENDING#{redeemedAt}` — sparse, containing only pending rows — is the escape hatch, and it does not change the API.

Scoping the query to the caller's own re-derived `householdId` is what enforces cross-household isolation: a redemption in another household is simply not in the result set, and comes back as a 404 that discloses nothing.

### One route carrying a target state, not three verbs

`PATCH /redemptions/{redemptionId}` with `{"status": "fulfilled" | "pending" | "cancelled"}`. The handler maps the requested target to the single transition that reaches it, and refuses anything else:

| Target | Required current state | Write |
| --- | --- | --- |
| `fulfilled` | `pending` | conditional `Update` |
| `pending` | `fulfilled` (or absent — see below) | conditional `Update` |
| `cancelled` | `pending` | `TransactWriteItems`: `Update` redemption + `Update` balance |

Because each target has exactly one legal origin, the target *is* the transition — there is no ambiguity to resolve and no need for `POST /redemptions/{id}/fulfill`-style action routes. `cancelled` has no legal origin, which is what makes it terminal.

**The starting state is enforced by the write, not by the read that precedes it.** The `ConditionExpression` names the required current `status`, so the query is only for locating the item; a concurrent transition that lands in between fails the condition rather than being overwritten. This is the same reasoning as the completion marker in `record-completion.ts`, and gets the same treatment in verification. A failed condition surfaces as 409.

### Cancelling from `fulfilled` is refused

A parent who marked something fulfilled by mistake must un-fulfill it first, then cancel. This keeps exactly one path that returns points — `pending → cancelled` — so there is a single place where a refund can be issued and a single condition guarding it. Allowing `fulfilled → cancelled` would double the refund paths for no behavior a two-tap sequence does not already provide.

### The refund is transactional and reads its amount from the ledger

Cancellation is a `TransactWriteItems` of the status `Update` (conditioned on `status = 'pending'`) and `ADD #balance :points` on the balance item, mirroring `redeem-reward.ts` in reverse. The amount comes from `pointsSpent` on the redemption fetched in the locating query — not from the reward, which may have been repriced or deleted, and not from the request body.

Fulfil and un-fulfil touch no balance at all, so they are plain conditional `Update`s. The balance moved when the points were spent.

### Legacy rows are normalized on read, in one place

`list-redemptions.ts` maps `status: item.status ?? 'fulfilled'` before returning. Clients therefore never see an absent status and the `RedemptionStatus` enum can be non-optional, with no per-call-site defaulting to forget.

The write path has to tolerate the absent attribute too, so the un-fulfil condition is `attribute_not_exists(#status) OR #status = :fulfilled` — the one place the raw shape leaks. Nothing else can encounter it: fulfil and cancel both require `status = 'pending'`, which a legacy row can never satisfy.

*Alternative — a one-off backfill writing `status: 'fulfilled'` onto every existing row.* Rejected as the primary mechanism: it is a mutating script against real family data to avoid two defaults. Read-normalization is idempotent and needs no coordination with the deploy. A backfill remains available later as pure cleanup, at which point the `attribute_not_exists` clause can go.

### The parent check moves into `common/auth.ts`

`requireParent(householdId, uid)` reads the household `METADATA` item and throws `HttpError(403)` unless `members[uid].role === 'parent'` — the check currently inlined in `generate-invite-code.ts`, which adopts the helper as part of this change. The member map is the right source: it is the household's own record of who its parents are, and it is what the existing check already uses.

The user profile item also carries a `role`, but it is a per-user convenience copy; the household's member map is authoritative.

### Realtime needs no changes

A status `Update` rewrites the `REDEMPTION#` item, which the stream reports and `resourceFor` already maps to `redemptions`. A cancellation additionally touches `BALANCE#` → `balances`. `RewardStore.observe` already refetches on both. A child's redemption therefore lands in a parent's queue, and a fulfillment leaves another parent's queue, with no transport work.

### iOS: pending state is derived, and the notifier is a pure observer

`RewardStore` gains `pendingRedemptions` as a computed property over the redemptions it already holds — filtered to `.pending`, sorted oldest-first — and the three transition methods go through the existing `perform { }` helper, which refetches on success and routes failures to `errorMessage`. No new fetch, no new store.

`PendingRedemptionNotifier` observes the store's published redemptions and posts notifications. **It must never call `refresh()`.** CLAUDE.md records the failure mode: a view or observer that refetches in reaction to a `@Published` change of a store it observes never lets the app go idle, and XCUITest then hangs for minutes on a single tap. The notifier reads and posts; the refetch is always someone else's.

Deduplication is by redemption id, persisted in `UserDefaults` keyed by household, so an app restart does not re-announce what the parent already saw. The set is pruned to ids still pending on each pass, which bounds it to the queue's size rather than to all history.

The Rewards tab badge is `.badge(pendingCount)` on the tab item, parent-only; the app icon badge is set from the same count so it survives backgrounding.

### Notification permission is requested lazily, and foreground delivery is explicit

Authorization is requested the first time a parent's pending count goes from zero to non-zero — never at launch, when the ask has no context and is most likely refused. If it is refused, the queue and both badges still work; the app does not re-prompt.

Because the realistic case is a push arriving while the parent is using the app, the notification center delegate must return `[.banner, .sound, .badge]` from `willPresent`. Without it iOS suppresses the banner for a foreground app and the feature is invisible in exactly the situation it fires most.

## Risks / Trade-offs

- **A local notification cannot fire while the app is not running.** → Accepted and stated in the proposal's non-goals. The app icon badge is set before backgrounding, so a closed app still shows a count; the banner is best-effort on top. Remote push is the follow-up if the badge proves insufficient.
- **Locating a redemption is a full range query over the household's history.** → Bounded by a family's redemption count and paginated the same way `list-redemptions.ts` already is. The sparse-GSI escape hatch above is API-compatible.
- **An old client redeeming against the new backend creates a `pending` redemption whose state its own UI cannot show.** → Harmless and self-correcting: the entry appears in that client's history exactly as before, and any updated parent device can resolve it. No forced-upgrade gate needed.
- **A refund could double-apply if the condition were dropped or weakened.** → The `status = 'pending'` condition inside the transaction is the only thing standing between one cancel and two. `verify-redemption-lifecycle.mjs` fires concurrent cancels and asserts a single refund, the same way `verify-duplicate-guard.mjs` guards completions.
- **The notifier is new code observing a store that drives the UI.** → It is strictly read-only with respect to the store, per the decision above. The UI test that fulfills a redemption is also the regression test for the idle loop: if the notifier ever triggers a refetch, that test times out synthesizing a tap.
- **`UserDefaults` announcement state is per-device.** → Two parent devices each announce independently, which is the desired behavior; there is no shared read state to coordinate.

## Migration Plan

No data migration. New attributes on an existing item shape, and the absent-status default is applied on read.

1. Deploy the backend to an ephemeral stage and run `verify-redemption-lifecycle.mjs` plus the existing `verify-duplicate-guard.mjs` and `verify-realtime.mjs`.
2. Deploy the backend to `prod` ahead of the client. Old clients keep working: they ignore the new fields, and redemptions they create become pending and are resolvable from any updated device.
3. Ship the client.

**Rollback:** revert the client, and revert the backend to the previous Lambda versions. `status` attributes left on rows are inert to the old code, which reads redemptions without reference to them. The one visible consequence of a rollback after a cancellation is a cancelled entry still listed in history with its points already returned — a discrepancy in the old client's display only, not in the stored balance, which stays correct either way.

## Open Questions

- Whether the app icon badge should count only pending redemptions or eventually fold in other parent-facing work. Deferred: it does not affect the API, the specs, or the task breakdown, and the count is computed in one place.
