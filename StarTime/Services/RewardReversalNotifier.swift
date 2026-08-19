import Combine
import Foundation
import UserNotifications

/// Tells the member who redeemed a reward that a parent reversed it --
/// cancelled it (points refunded) or un-fulfilled it (back in the queue) --
/// on their own device, once per reversal.
///
/// Follows the same rule as `PendingRedemptionNotifier`: it only reads
/// `RewardStore` and must never call `refresh()` on it. Unlike that notifier,
/// this one does *not* set itself as the `UNUserNotificationCenter` delegate
/// -- `PendingRedemptionNotifier` already claims that role for the app (only
/// one delegate can be installed at a time), and its `willPresent` handler
/// isn't scoped to the notifications it personally posts. `MainTabView` runs
/// both notifiers for every session regardless of role, so that delegate is
/// always installed by the time this one has anything to announce.
@MainActor
final class RewardReversalNotifier: ObservableObject {
    // Deliberately no @Published anything, for the same reason as
    // PendingRedemptionNotifier: this is a @StateObject on MainTabView, and
    // re-rendering the view that owns the stores would risk the refetch loop
    // the "never call refresh()" rule exists to avoid.

    private let center = UNUserNotificationCenter.current()
    private var subscription: AnyCancellable?
    private var householdId: String?
    private var uid: String?

    /// Subscribes to the store's redemptions. Safe to call repeatedly --
    /// MainTabView re-runs its household task on every household change.
    func start(store: RewardStore, householdId: String, uid: String) {
        self.householdId = householdId
        self.uid = uid

        subscription = store.$redemptions
            .sink { [weak self] redemptions in
                self?.handle(redemptions)
            }
    }

    /// Sign-out. Forgets what this device announced, so a different member
    /// signing in later starts clean.
    func stop() {
        subscription = nil
        if let householdId {
            UserDefaults.standard.removeObject(forKey: Self.announcedKey(householdId))
        }
        householdId = nil
        uid = nil
    }

    private func handle(_ redemptions: [Redemption]) {
        guard let householdId, let uid else { return }

        // Only this member's own reversed redemptions -- unlike the parent
        // queue (household-wide), this is scoped per person.
        let reversed: [(redemption: Redemption, key: String)] = redemptions.compactMap { redemption in
            guard redemption.redeemedByUID == uid, let id = redemption.id else { return nil }
            // Keyed by id plus the event's own timestamp, not bare id:
            // un-fulfilling isn't terminal, so the same redemption can need a
            // fresh announcement more than once. `cancelledAt` is set exactly
            // once (cancelled is terminal), so that key never repeats.
            if redemption.status == .cancelled, let cancelledAt = redemption.cancelledAt {
                return (redemption, "\(id):\(cancelledAt.timeIntervalSince1970)")
            }
            if redemption.status == .pending, let unfulfilledAt = redemption.unfulfilledAt {
                return (redemption, "\(id):\(unfulfilledAt.timeIntervalSince1970)")
            }
            return nil
        }

        let key = Self.announcedKey(householdId)
        let announced = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let currentKeys = Set(reversed.map(\.key))
        let unannounced = reversed.filter { !announced.contains($0.key) }

        // Pruned to keys still represented among current reversals, the same
        // way the pending queue's announced set is pruned -- otherwise this
        // grows for the life of the household.
        //
        // Recorded synchronously, before posting below, for the same reason
        // as the pending-queue notifier: two refetches landing back to back
        // must not both see the same reversal as unannounced and both post
        // it.
        let retained = announced.intersection(currentKeys)
        UserDefaults.standard.set(Array(retained.union(currentKeys)), forKey: key)

        guard !unannounced.isEmpty else { return }
        Task { await announce(unannounced) }
    }

    private func announce(_ reversals: [(redemption: Redemption, key: String)]) async {
        // Asked for at the first moment there is actually something to say.
        // iOS only ever shows this once, so a member who declines isn't
        // re-asked.
        guard await requestAuthorizationIfNeeded() else { return }

        for (redemption, key) in reversals {
            let content = UNMutableNotificationContent()
            content.title = "Reward reversed"
            if let note = redemption.reversalNote, !note.isEmpty {
                content.body = "\(redemption.rewardName): \(note)"
            } else {
                content.body = "A parent reversed your \(redemption.rewardName) request."
            }
            content.sound = .default

            // The dedupe key itself: a re-post of the same event replaces
            // rather than duplicates.
            let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// Mirrors `PendingRedemptionNotifier`'s suppression: a UI test that
    /// drives a reversal would otherwise hit this prompt on the redeeming
    /// member's session too.
    private static var isPromptSuppressed: Bool {
        ProcessInfo.processInfo.environment["STARTIME_SUPPRESS_NOTIFICATION_PROMPT"] == "1"
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard !Self.isPromptSuppressed else { return false }
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            // The redemption's own history row still shows the reversal and
            // its note regardless.
            return false
        default:
            return true
        }
    }

    private static func announcedKey(_ householdId: String) -> String {
        "announcedReversedRedemptions.\(householdId)"
    }
}
