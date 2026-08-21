import Combine
import Foundation
import UserNotifications

/// Tells a chore's assignee that one of their completions was reversed --
/// a checklist item unchecked after the day already completed, taking the
/// points back -- on their own device, once per reversal.
///
/// The completion-side counterpart to `RewardReversalNotifier`, and follows
/// the same rules: it only reads `ChoreStore` and must never call
/// `refresh()` on it, declares no `@Published` state, and does not install
/// itself as the `UNUserNotificationCenter` delegate -- `MainTabView` always
/// runs `PendingRedemptionNotifier`, which already claims that role, so its
/// `willPresent` handler covers this notifier's posts too.
///
/// Notifies the assignee even when they performed the reversal themselves --
/// any household member may uncheck an item, including the assignee fixing
/// their own mis-tap, and this notifier doesn't distinguish who acted.
@MainActor
final class ChoreCompletionReversalNotifier: ObservableObject {
    private let center = UNUserNotificationCenter.current()
    private var subscription: AnyCancellable?
    private var householdId: String?
    private var uid: String?

    /// Subscribes to the store's completions. Safe to call repeatedly --
    /// MainTabView re-runs its household task on every household change.
    func start(store: ChoreStore, householdId: String, uid: String) {
        self.householdId = householdId
        self.uid = uid

        subscription = store.$completions
            .sink { [weak self] completions in
                self?.handle(completions)
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

    private func handle(_ completions: [ChoreCompletion]) {
        guard let householdId, let uid else { return }

        // Only this member's own reversed completions -- scoped per person,
        // the same as the redemption reversal notifier.
        let reversed: [(completion: ChoreCompletion, key: String)] = completions.compactMap { completion in
            guard completion.completedByUID == uid, let id = completion.id, let reversedAt = completion.reversedAt else {
                return nil
            }
            return (completion, "\(id):\(reversedAt.timeIntervalSince1970)")
        }

        let key = Self.announcedKey(householdId)
        let announced = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let currentKeys = Set(reversed.map(\.key))
        let unannounced = reversed.filter { !announced.contains($0.key) }

        // Pruned to keys still represented among current reversals, and
        // recorded synchronously before posting -- same reasoning as
        // RewardReversalNotifier: two refetches landing back to back must
        // not both see the same reversal as unannounced.
        let retained = announced.intersection(currentKeys)
        UserDefaults.standard.set(Array(retained.union(currentKeys)), forKey: key)

        guard !unannounced.isEmpty else { return }
        Task { await announce(unannounced) }
    }

    private func announce(_ reversals: [(completion: ChoreCompletion, key: String)]) async {
        // Asked for at the first moment there is actually something to say.
        guard await requestAuthorizationIfNeeded() else { return }

        for (completion, key) in reversals {
            let content = UNMutableNotificationContent()
            content.title = "Chore undone"
            if let note = completion.reversalNote, !note.isEmpty {
                content.body = "\(completion.choreTitle): \(note)"
            } else {
                content.body = "\(completion.choreTitle) was unchecked, and the points were taken back."
            }
            content.sound = .default

            // The dedupe key itself: a re-post of the same event replaces
            // rather than duplicates.
            let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// Mirrors `RewardReversalNotifier`'s suppression: a UI test that drives
    /// a reversal would otherwise hit this prompt on the assignee's session.
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
            // The completion's own history row still shows the reversal and
            // its note regardless.
            return false
        default:
            return true
        }
    }

    private static func announcedKey(_ householdId: String) -> String {
        "announcedReversedCompletions.\(householdId)"
    }
}
