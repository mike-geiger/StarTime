## 1. Backend — redemption lifecycle

- [x] 1.1 In `backend/cdk/lambda/rewards/update-redemption-status.ts`, parse an optional `note` (string) from the PATCH body alongside `status`; reject with 400 (redemption unchanged) if it exceeds 500 characters.
- [x] 1.2 Extend the `pending → cancelled` transaction to set `reversalNote` on the redemption item when a note was supplied, alongside the existing `cancelledAt`/`cancelledByUID`.
- [x] 1.3 Extend the `fulfilled → pending` (un-fulfil) transition to set `unfulfilledAt` (a fresh timestamp on every un-fulfil) and `reversalNote` when supplied, alongside the existing removal of `fulfilled*` attributes.
- [x] 1.4 Extend the `pending → fulfilled` transition to remove any existing `reversalNote` (it no longer applies once the redemption is resolved again). Leave `unfulfilledAt` alone — it's an internal dedup timestamp, not display data, and gets overwritten by the next un-fulfil regardless.
- [x] 1.5 Ignore (don't store, don't error) a `note` supplied alongside `status: 'fulfilled'` — only the cancel and un-fulfil branches read it.
- [x] 1.6 Update `presentRedemption` in `backend/cdk/lambda/rewards/redemptions.ts` to include `reversalNote` and `unfulfilledAt` in the shape returned by every endpoint that presents a redemption. (Already satisfied — `presentRedemption` spreads all item attributes through generically, so no code change was needed.)

## 2. Backend verification

- [x] 2.1 Extend `backend/cdk/scripts/verify-redemption-lifecycle.mjs`: cancelling with a note returns `reversalNote` in the response; cancelling without one leaves it absent.
- [x] 2.2 Assert un-fulfilling with a note sets `reversalNote` and a fresh `unfulfilledAt`; re-fulfil and un-fulfil a second time, and assert `unfulfilledAt` changes between the two events.
- [x] 2.3 Assert fulfilling a redemption that carries a `reversalNote` clears it.
- [x] 2.4 Assert a note over 500 characters is refused with 400 and the redemption is left unchanged.
- [x] 2.5 Assert a note supplied alongside `status: 'fulfilled'` is silently ignored — the transition succeeds and no note is stored.
- [x] 2.6 Run the script via `backend/scripts/with-ephemeral-stack.sh` alongside the existing verification scripts. (Ran clean: `REDEMPTION LIFECYCLE OK`, all checks passed including the new note/dedup assertions.)

## 3. iOS — model and service

- [x] 3.1 Add `reversalNote: String?` and `unfulfilledAt: Date?` to `StarTime/Models/Redemption.swift`.
- [x] 3.2 Extend `RewardService.updateRedemptionStatus(redemptionId:status:)` and its request body struct to accept and send an optional `note`.
- [x] 3.3 Extend `RewardStore.cancel(_:)` and `RewardStore.unfulfill(_:)` to accept an optional note and pass it through.

## 4. iOS — views

- [x] 4.1 Replace the plain two-button `.confirmationDialog` for cancel in `StarTime/Views/RewardsView.swift` with an `.alert` embedding a `TextField` for an optional note, keeping the existing "Cancel and return N points" / "Keep it" buttons and messaging.
- [x] 4.2 Add a matching confirmation for un-fulfil (none exists today), same `.alert` + `TextField` shape, with "Un-fulfill and return to queue" / "Keep as fulfilled" buttons (named by consequence like cancel's confirm button, and distinct from the swipe action's own "Un-fulfill" label to avoid a duplicate-label lookup collision), triggered from `unfulfillRedemptionButton-<id>`.
- [x] 4.3 Show `reversalNote`, when present, on the corresponding history row alongside its existing status pill. (Also shown on the parent's pending-queue row, since an un-fulfilled-with-note redemption reappears there rather than in history.)
- [x] 4.4 Reset the note draft state on dismissal or after a successful submission, so a stale draft can't leak into the next confirmation.

## 5. iOS — notifications

- [x] 5.1 Create `StarTime/Services/RewardReversalNotifier.swift`: a `@MainActor` observer of `RewardStore.$redemptions`, mirroring `PendingRedemptionNotifier`'s shape (including that it must never call `refresh()` on the store it observes).
- [x] 5.2 Filter to redemptions where `redeemedByUID` matches the signed-in member's own uid, then to those that are `.cancelled` or (`.pending` with `unfulfilledAt` set).
- [x] 5.3 Compute each candidate's dedup key from its id plus `cancelledAt` or `unfulfilledAt` (whichever applies); diff against a `UserDefaults`-persisted announced-key set (new key, e.g. `announcedReversedRedemptions.<householdId>`), announcing only keys not already present.
- [x] 5.4 Post one `UNMutableNotificationContent` per newly announced reversal, naming the reward in the title, including `reversalNote` in the body when present and a generic message otherwise; use the dedup key as the notification identifier.
- [x] 5.5 Request notification authorization lazily the first time there's a reversal to announce, honoring `STARTIME_SUPPRESS_NOTIFICATION_PROMPT`, and never re-prompt after a refusal.
- [x] 5.6 Prune the announced-key set to keys still represented among current redemptions on each pass.
- [x] 5.7 Wire the notifier into `StarTime/Views/MainTabView.swift` alongside the existing stores and `PendingRedemptionNotifier`, started/stopped on the same household lifecycle, clearing its announced-key state on sign-out.

## 6. Tests and docs

- [x] 6.1 Add a UI test: a parent cancels a pending redemption with a note; the redeeming member's history row shows that note.
- [x] 6.2 Add a UI test: a parent un-fulfils a fulfilled redemption with a note via the new confirmation; it reappears in the parent's pending queue and the redeeming member's history shows the note.
- [x] 6.3 Run the full UI suite against an ephemeral stack with a simulator UDID destination, confirming no test regresses into a "Timed out while synthesizing event" failure (would indicate the new notifier introduced a refetch loop). (First run caught a pre-existing test that assumed un-fulfil had no confirmation — fixed; second run: 14/14 tests passed, no regressions.)
- [x] 6.4 Update CLAUDE.md: the `reversalNote`/`unfulfilledAt` attributes and the note's 500-character cap, `RewardReversalNotifier` alongside the existing notification section, and `verify-redemption-lifecycle.mjs`'s extended coverage.
