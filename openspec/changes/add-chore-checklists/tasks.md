## 1. Backend — data model

- [ ] 1.1 In `backend/cdk/lambda/chores/save-chore.ts`, accept an optional `items` array (`{id, title}`) in the request body; validate each item has a non-empty `id` and `title` and that ids are unique within the chore. Item ids are generated client-side (there's no per-item endpoint — items travel through the existing whole-object `PUT`/`POST /chores` overwrite), so the server validates rather than generates them.
- [ ] 1.2 Add `Keys.checklistProgress(householdId, choreId, scheduledDate)` to `backend/cdk/lambda/common/dynamo.ts`, mirroring `Keys.completionMarker`: `SK: CHECKLIST#{choreId}#{scheduledDate}`.
- [ ] 1.3 Extend `Keys.completionMarker`'s call site(s) to also store `completedAt` on the marker alongside the existing `completionId`, so `completedAt` + `completionId` + `choreId` reconstructs a completion's exact `SK` (`COMPLETION#{completedAt}#{completionId}`) for a point lookup without a range query.

## 2. Backend — checklist completion

- [ ] 2.1 Add a shared helper (e.g. `backend/cdk/lambda/chores/common/complete-checklist-day.ts`) that runs the closing transaction — `Put ChoreCompletion` + `ADD balance` + `Put COMPLETEDON#` marker (with `completedAt`/`completionId`) under `attribute_not_exists(PK)` — so it isn't duplicated between the check-item path and the explicit complete action.
- [ ] 2.2 Create `backend/cdk/lambda/chores/check-checklist-item.ts` (`POST /chores/{choreId}/checklist/items/{itemId}/check`, `scheduledDate` as a query parameter, mirroring how `POST /completions` already trusts the client for the local calendar day): derive `householdId` from the caller, `GetItem` the chore and reject (400) if it isn't a checklist chore or `itemId` isn't one of its items, then `UpdateCommand` an unconditional `ADD checkedItemIds :itemId` on the checklist-progress item (creating it if absent).
- [ ] 2.3 After the update, do a strongly consistent re-read of the checklist-progress item; if `checkedItemIds` now covers every id in the chore's current `items` and no `COMPLETEDON#` marker exists for that day, call the helper from 2.1. Catch a `TransactionCanceledException` from the helper and treat it as a no-op (a concurrent request already closed it) rather than an error.
- [ ] 2.4 Create `backend/cdk/lambda/chores/uncheck-checklist-item.ts` (`POST /chores/{choreId}/checklist/items/{itemId}/uncheck`, same query parameter): accept an optional `note`, rejecting with 400 (no writes performed) if it exceeds 500 characters, matching the redemption-reversal cap. Then run an unconditional `UpdateCommand` `DELETE checkedItemIds :itemId`.
- [ ] 2.5 After the delete, `GetItem` the `COMPLETEDON#` marker for that day. If absent, return (pre-completion uncheck, nothing further to do). If present, use its `completedAt`/`completionId` to `GetItem` the `ChoreCompletion` directly by key, then run a reversal `TransactWriteItems`: `Update` the completion (`SET reversedAt, reversedByUID, reversalNote` under `attribute_not_exists(reversedAt)`), `ADD balance :negativePoints` using the completion's own `pointsAwarded` (uncapped, no floor), and `Delete` the `COMPLETEDON#` marker. Catch a cancelled transaction as a no-op (already reversed by a concurrent uncheck).
- [ ] 2.6 Create `backend/cdk/lambda/chores/complete-checklist.ts` (`POST /chores/{choreId}/checklist/complete`, same query parameter): re-derive `householdId`, read the chore and checklist-progress item, and if `checkedItemIds` doesn't cover every required item, reject (409). Otherwise, if no `COMPLETEDON#` marker exists yet, call the helper from 2.1; if one already exists, return success as a no-op (already complete).
- [ ] 2.7 Register the three new routes and their Lambdas alongside the existing `/chores` and `/completions` routes (`backend/cdk/lib/api-stack.ts` or wherever those are currently wired).

## 3. Backend — cascade delete and realtime

- [ ] 3.1 In `backend/cdk/lambda/household/delete-account.ts`, add `'CHECKLIST#'` to the cascade-delete prefix list, alongside `'COMPLETEDON#'`.
- [ ] 3.2 In `backend/cdk/lambda/realtime/stream-fanout.ts`'s `resourceFor`, add `if (sortKey.startsWith('CHECKLIST#')) return 'chores';` so checklist-progress writes ride the same `chores` invalidation `ChoreStore` already subscribes to.

## 4. Backend verification

- [ ] 4.1 Create `backend/cdk/scripts/verify-checklist-completion.mjs`: create a checklist chore with 3 items, check them one at a time, and assert no `ChoreCompletion`/balance credit exists until the 3rd check, at which point exactly one completion is recorded and the balance increases by exactly the chore's points.
- [ ] 4.2 Extend it: with 2 of 3 items already checked, fire concurrent check requests for the two different remaining items (there's only one remaining in a 3-item chore — use a 4-item chore with 2 already checked so two distinct concurrent checks are both "the last one needed"), and assert exactly one completion is recorded and exactly one credit is applied — the race the design's write-then-strongly-consistent-re-read approach exists to close.
- [ ] 4.3 Extend it: uncheck an item on a completed checklist chore, assert the completion is marked reversed, the balance decreases by exactly the credited amount, and the `COMPLETEDON#` marker is gone; re-check every item and assert it completes and credits again.
- [ ] 4.4 Extend it: spend the credited points (e.g. redeem a reward) before reversing the completion, and assert the reversal still succeeds and the balance goes negative rather than being refused or floored at zero.
- [ ] 4.5 Extend it: on a completed checklist chore, fire concurrent uncheck requests against two different already-checked items, and assert exactly one reversal (one debit), not two.
- [ ] 4.6 Extend it: with a checklist chore fully checked and completed, remove one of its items via `PUT /chores/{choreId}` so the remaining checked items already cover what's left required; assert the chore does not auto-complete a second time; call the explicit complete endpoint against an *unfinished* checklist and assert it's refused; against the now-already-satisfied one and assert it succeeds.
- [ ] 4.7 Extend it: assert a chore with no `items` behaves exactly as `record-completion.ts`'s existing flow (regression guard for the non-checklist path).
- [ ] 4.8 Run the script via `backend/scripts/with-ephemeral-stack.sh` alongside the existing verification scripts.

## 5. iOS — models and services

- [ ] 5.1 Add `ChecklistItem: Identifiable, Codable, Equatable` (`id`, `title`) and `items: [ChecklistItem]` (default `[]`) to `StarTime/Models/Chore.swift`.
- [ ] 5.2 Add `reversedAt: Date?`, `reversedByUID: String?`, `reversalNote: String?` to `StarTime/Models/ChoreCompletion.swift`.
- [ ] 5.3 Add a model for a day's checklist progress (e.g. `ChoreChecklistProgress` with `choreId`, `scheduledDate`, `checkedItemIds: Set<String>`).
- [ ] 5.4 Add to `StarTime/Services/ChoreService.swift`: `checkChecklistItem(choreId:itemId:scheduledDate:)`, `uncheckChecklistItem(choreId:itemId:scheduledDate:note:)`, `completeChecklist(choreId:scheduledDate:)`, and a fetch for checklist progress (scoped to the same 60-day window `fetchCompletions(since:)` already uses, or per-chore-per-day — whichever keeps `ChoreStore.refreshNow()` to its existing two-call shape most naturally).

## 6. iOS — store

- [ ] 6.1 Extend `ChoreStore` with published checklist-progress state, refreshed alongside `chores`/`completions` in `refreshNow()`.
- [ ] 6.2 Add `ChoreStore.checkItem(_:itemId:)`, `uncheckItem(_:itemId:note:)`, `markChecklistComplete(_:)`, following the same `perform(...)`/refetch-after-write pattern as `complete(_:assigneeName:)`.
- [ ] 6.3 Update `ChoreStore.isCompletedToday(_:)` and `ChoreStore.streak(for:)` to treat a completion with `reversedAt != nil` as not done for that day.
- [ ] 6.4 Add a helper (e.g. `ChoreStore.isChecklistAwaitingExplicitCompletion(_:)`) that's true when today's checked items already cover the chore's current required items but no completion has landed yet — this is what shows the "Mark Complete" affordance.

## 7. iOS — views

- [ ] 7.1 In `StarTime/Views/AddEditChoreView.swift`, add a checklist items editor (add/remove/reorder/rename), generating a UUID for each newly added item client-side, shown when editing a checklist chore or turning a chore into one.
- [ ] 7.2 In `StarTime/Views/ChoresView.swift`, render a checklist chore with per-item checkboxes and progress instead of the single Complete button; leave non-checklist chores unchanged.
- [ ] 7.3 Add the explicit "Mark Complete" affordance, visible only per `isChecklistAwaitingExplicitCompletion`, wired to `markChecklistComplete`.
- [ ] 7.4 Add accessibility identifiers for the new controls following the existing naming convention (e.g. `checklistItemCheckbox-<choreId>-<itemId>`, `markChecklistCompleteButton-<choreId>`).
- [ ] 7.5 Add an uncheck confirmation with an optional note field when unchecking an item would reverse an already-completed chore (mirroring `RewardsView`'s cancel/un-fulfil `.alert` + `TextField`), skipping the confirmation for a plain pre-completion uncheck.

## 8. iOS — reversal notifications

- [ ] 8.1 Create `StarTime/Services/ChoreCompletionReversalNotifier.swift`: a `@MainActor` observer of `ChoreStore.$completions`, mirroring `RewardReversalNotifier`'s shape — it must never call `refresh()` on the store it observes and declares no `@Published` state of its own.
- [ ] 8.2 Filter to completions where `completedByUID` matches the signed-in member's own uid and `reversedAt != nil`; dedup key is `id` plus `reversedAt`, diffed against a `UserDefaults`-persisted announced-key set.
- [ ] 8.3 Post one notification per newly announced reversal, naming the chore and including `reversalNote` when present; request notification authorization lazily on the first reversal to announce, honoring `STARTIME_SUPPRESS_NOTIFICATION_PROMPT`, never re-prompting after a refusal; prune the announced-key set to keys still represented.
- [ ] 8.4 Wire the notifier into `StarTime/Views/MainTabView.swift` alongside the existing stores and notifiers, started/stopped on the same household lifecycle, cleared on sign-out.

## 9. Tests and docs

- [ ] 9.1 UI test: a parent creates a checklist chore with 3 items; the assigned child checks all 3; assert it completes and credits points exactly once.
- [ ] 9.2 UI test: check 2 of 3 items and assert no credit or completion yet; check the last one and assert both.
- [ ] 9.3 UI test: uncheck an item after completion; assert the completion reverses, the balance decreases, and the chore becomes checkable again; re-check every item and assert it completes and credits again.
- [ ] 9.4 UI test (via `makeApp()` for `STARTIME_SUPPRESS_NOTIFICATION_PROMPT`): a parent reverses a child's completed checklist chore with a note; assert the child's device shows the reversal alert including the note.
- [ ] 9.5 UI test: edit a checklist chore's items so the already-checked items satisfy the new list; assert it does not auto-complete; tap "Mark Complete" and assert it now completes and credits.
- [ ] 9.6 Run the full UI suite against an ephemeral stack with a simulator UDID destination; confirm no test regresses into a "Timed out while synthesizing event" failure.
- [ ] 9.7 Update CLAUDE.md: the checklist item model, the two-step check/uncheck-then-evaluate design and why it avoids a retry loop, the `CHECKLIST#` item and its cascade-delete/realtime additions, the "append-only except for a recorded reversal" nuance on `ChoreCompletion`, and the third notifier.
