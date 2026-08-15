## 1. Backend — shared groundwork

- [ ] 1.1 Add `requireParent(householdId, uid)` to `backend/cdk/lambda/common/auth.ts`: read the household `METADATA` item and throw `HttpError(403, ...)` unless `members[uid].role === 'parent'`.
- [ ] 1.2 Replace the inlined parent check in `backend/cdk/lambda/household/generate-invite-code.ts` with `requireParent`, keeping its existing 403 message.
- [ ] 1.3 Add a `RedemptionStatus` union (`'pending' | 'fulfilled' | 'cancelled'`) and a `findRedemptionById(householdId, redemptionId)` helper that range-queries `SK BETWEEN 'REDEMPTION#' AND 'REDEMPTION#~'` (paginating like `list-redemptions.ts`) and returns the matching item with its real `PK`/`SK`, or `undefined`.

## 2. Backend — redemption lifecycle

- [ ] 2.1 In `redeem-reward.ts`, write `status: 'pending'` on the new redemption item. Leave the balance transaction and its `ConditionExpression` untouched.
- [ ] 2.2 In `list-redemptions.ts`, normalize each returned item to `status: item.status ?? 'fulfilled'` so no client ever sees an absent state.
- [ ] 2.3 Create `backend/cdk/lambda/rewards/update-redemption-status.ts`: derive uid and householdId, `requireParent`, validate the body's target `status` against the three legal values (400 otherwise), locate the redemption via 1.3 (404 if absent).
- [ ] 2.4 Implement the `pending → fulfilled` transition as a conditional `Update` (`#status = 'pending'`) setting `status`, `fulfilledAt`, `fulfilledByUID`, `fulfilledByName`.
- [ ] 2.5 Implement the `fulfilled → pending` transition as a conditional `Update` (`attribute_not_exists(#status) OR #status = 'fulfilled'`) setting `status: 'pending'` and removing the `fulfilled*` attributes.
- [ ] 2.6 Implement the `pending → cancelled` transition as a `TransactWriteItems`: conditional `Update` on the redemption (`#status = 'pending'`) setting `status`, `cancelledAt`, `cancelledByUID`; plus `ADD #balance :points` on the balance item, where `:points` is the redemption's stored `pointsSpent`.
- [ ] 2.7 Map `ConditionalCheckFailedException` and `TransactionCanceledException` to `409` with a message naming the redemption's actual state ("that request was already fulfilled" / "already cancelled").
- [ ] 2.8 Wire `PATCH /redemptions/{redemptionId}` to the new handler in `backend/cdk/lib/api-stack.ts`, behind the Cognito authorizer like every other route.

## 3. Backend verification

- [ ] 3.1 Create `backend/cdk/scripts/verify-redemption-lifecycle.mjs` modeled on `verify-duplicate-guard.mjs`: sign up a parent, create a household, generate a child invite code, sign up a second identity and join as the child, and give the child a balance via a chore completion.
- [ ] 3.2 Assert the happy path: redeeming yields `status: 'pending'` and debits the balance immediately; fulfilling yields `fulfilled` with the balance unchanged; un-fulfilling returns it to `pending`.
- [ ] 3.3 Assert cancellation refunds exactly `pointsSpent` and leaves the entry in the ledger as `cancelled`.
- [ ] 3.4 Assert the illegal transitions: cancelling a `fulfilled` redemption is 409, any transition on a `cancelled` one is 409, and an unknown redemption id is 404.
- [ ] 3.5 Assert authorization: the child's token gets 403 on every transition, including against their own redemption, and the redemption is unchanged afterwards.
- [ ] 3.6 Assert concurrency: fire 5 simultaneous cancels of one pending redemption and require exactly one 200, four 409s, and a single refund in the balance.
- [ ] 3.7 Assert the legacy default: seed a redemption item with no `status` attribute (as `verify-migration-shape.mjs` seeds migrated shapes), read it back as `fulfilled`, and confirm un-fulfilling it succeeds.
- [ ] 3.8 Delete both accounts at the end, on success and failure paths alike.
- [ ] 3.9 Run the script and the existing `verify-duplicate-guard.mjs` / `verify-realtime.mjs` against one ephemeral stack via `backend/scripts/with-ephemeral-stack.sh`.

## 4. iOS — model and service

- [ ] 4.1 Add `RedemptionStatus: String, Codable` (`pending`, `fulfilled`, `cancelled`) and extend `Redemption` with `status`, `fulfilledAt`, `fulfilledByName`, `cancelledAt`. `status` is non-optional — the server always sends it.
- [ ] 4.2 Add `RewardService.updateRedemptionStatus(redemptionId:status:)` issuing `PATCH redemptions/{id}`.
- [ ] 4.3 Extend `RewardServiceError` with cases for 403 ("only a parent can do that") and 409 (already resolved elsewhere), mapped in that service method alongside the existing `insufficientBalance` mapping.

## 5. iOS — store

- [ ] 5.1 Add `RewardStore.pendingRedemptions` as a computed property over `redemptions`, filtered to `.pending` and sorted oldest `redeemedAt` first, plus `pendingCount`.
- [ ] 5.2 Add `fulfill(_:)`, `unfulfill(_:)`, and `cancel(_:)` routed through the existing `perform { }` helper so they refetch on success and surface failures via `errorMessage`.
- [ ] 5.3 Confirm no change is needed to `observe(_:)` — `redemptions` and `balances` are already in its filter — and leave `stop()` alone.

## 6. iOS — views

- [ ] 6.1 Add a "Waiting on you" section at the top of `RewardsView` for parents, listing each pending redemption's child name, reward, points, and relative request time, hidden entirely when the queue is empty.
- [ ] 6.2 Give each queued row a "Fulfilled" button and a destructive swipe action to cancel, with a confirmation on cancel since it returns points.
- [ ] 6.3 Add an "Un-fulfill" swipe action to fulfilled redemptions in the parent's view.
- [ ] 6.4 Show a status pill on the child's own "Redeemed" rows distinguishing awaiting-a-parent from received, and keep cancelled entries visible and labelled.
- [ ] 6.5 Add stable accessibility identifiers for anything a label query cannot target uniquely: `pendingRedemptionRow-<id>`, `fulfillRedemptionButton-<id>`, `cancelRedemptionButton-<id>`, `unfulfillRedemptionButton-<id>`.
- [ ] 6.6 Badge the Rewards tab in `MainTabView` with `rewardStore.pendingCount` for parents only.

## 7. iOS — notifications

- [ ] 7.1 Create `StarTime/Services/PendingRedemptionNotifier.swift`: a `@MainActor` observer of `RewardStore`'s published redemptions that posts a `UNNotificationRequest` per newly pending redemption. It must never call `refresh()` on the store it observes.
- [ ] 7.2 Persist announced redemption ids in `UserDefaults` keyed by household, and prune the set to ids still pending on every pass.
- [ ] 7.3 Request notification authorization the first time a parent's pending count goes from zero to non-zero; do not prompt at launch and do not re-prompt after a refusal.
- [ ] 7.4 Set the app icon badge from the same pending count so a backgrounded app still shows one.
- [ ] 7.5 Install a `UNUserNotificationCenterDelegate` returning `[.banner, .sound, .badge]` from `willPresent`, so the banner is not suppressed while the app is foregrounded.
- [ ] 7.6 Gate all of the above on the parent role, and clear the badge and announced-id state on sign-out.
- [ ] 7.7 Wire the notifier into `MainTabView` alongside the existing stores, started and stopped on the same household lifecycle.

## 8. Tests and docs

- [ ] 8.1 Add a UI test: a parent redeems on a child's behalf, sees the queue row and the tab badge, taps "Fulfilled", and watches the row leave the queue. Clean up the account on every path.
- [ ] 8.2 Add a UI test for cancel: a parent cancels a pending redemption and the child's balance returns to its prior value on screen.
- [ ] 8.3 Run the full UI suite against an ephemeral stack with a simulator UDID destination, per CLAUDE.md, and confirm no test regresses into a "Timed out while synthesizing event" failure — that would mean the notifier introduced a refetch loop.
- [ ] 8.4 Update CLAUDE.md: the redemption item's new attributes, the read-normalized legacy default, `PATCH /redemptions/{redemptionId}` and its parent-only rule, the single `pending → cancelled` refund path as an invariant, and `verify-redemption-lifecycle.mjs` in the verification-script list.
