import Combine
import Foundation
import UserNotifications

/// Tells a parent that redemptions are waiting on them, without making them
/// open the Rewards tab to find out.
///
/// **This observes `RewardStore` and never writes to it.** In particular it
/// must never call `refresh()`: a refetch triggered by a `@Published` change
/// of an observed store re-publishes, which re-triggers the refetch, and the
/// app never goes idle -- the failure that once made XCUITest hang for 900+
/// seconds on a single tap. Reading and posting is all this does; refetching
/// is always somebody else's job.
///
/// A local notification can only be posted by a running app, so this covers
/// "a request arrived while the parent was using the app" and "the parent
/// came back and something happened while they were away". A parent whose
/// app is fully closed sees the app-icon badge, set before they left.
@MainActor
final class PendingRedemptionNotifier: NSObject, ObservableObject {
    // Deliberately no @Published anything: MainTabView holds this as a
    // @StateObject, and a notifier that re-rendered the view that owns the
    // stores would be one more edge in exactly the cycle described above.

    private let center = UNUserNotificationCenter.current()
    private var subscription: AnyCancellable?
    private weak var store: RewardStore?
    private var householdId: String?
    private var isParent = false

    override init() {
        super.init()
        center.delegate = self
    }

    /// Subscribes to the store's redemptions. Safe to call repeatedly --
    /// MainTabView re-runs its household task on every household change.
    func start(store: RewardStore, householdId: String, isParent: Bool) {
        self.store = store
        self.householdId = householdId
        self.isParent = isParent

        subscription = store.$redemptions
            .sink { [weak self] redemptions in
                self?.handle(redemptions)
            }
    }

    /// The role can land after the household does -- creating a household
    /// assigns `household` before `profile` -- so it is updated here rather
    /// than captured once at `start`. Otherwise a parent who just created
    /// their household would be treated as a child until the next sign-in.
    func setIsParent(_ isParent: Bool) {
        guard self.isParent != isParent else { return }
        self.isParent = isParent
        if let store { handle(store.redemptions) }
    }

    /// Sign-out. Drops the badge and forgets what this device announced, so
    /// a different family signing in on the same device starts clean.
    func stop() {
        subscription = nil
        setBadge(0)
        if let householdId {
            UserDefaults.standard.removeObject(forKey: Self.announcedKey(householdId))
        }
        householdId = nil
        isParent = false
    }

    private func handle(_ redemptions: [Redemption]) {
        // A child's device has no queue and is never alerted, whatever is
        // pending elsewhere in the household.
        guard isParent, let householdId else {
            setBadge(0)
            return
        }

        let pending = redemptions.filter { $0.status == .pending }
        setBadge(pending.count)

        let key = Self.announcedKey(householdId)
        let announced = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let unannounced = pending.filter { redemption in
            guard let id = redemption.id else { return false }
            return !announced.contains(id)
        }

        // Pruned to what's still pending before adding the new ids, so this
        // stays the size of the queue rather than growing with all history.
        //
        // Recorded here, synchronously, *before* the posting below rather
        // than after it succeeds. Posting is async, and two refetches
        // landing back to back would otherwise both see the same request as
        // unannounced and both post it -- exactly the duplicate this set
        // exists to prevent. The cost is that a request is considered
        // announced even if permission was refused and nothing was shown,
        // which is the better failure: a missed banner rather than a
        // repeated one.
        let pendingIds = Set(pending.compactMap(\.id))
        let retained = announced.intersection(pendingIds)
        UserDefaults.standard.set(
            Array(retained.union(unannounced.compactMap(\.id))),
            forKey: key
        )

        guard !unannounced.isEmpty else { return }
        Task { await announce(unannounced) }
    }

    private func announce(_ redemptions: [Redemption]) async {
        // Asked for at the first moment there is actually something to say,
        // rather than at launch where the prompt has no context. iOS only
        // ever shows this once, so a parent who declines is not re-asked.
        guard await requestAuthorizationIfNeeded() else { return }

        for redemption in redemptions {
            guard let id = redemption.id else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Reward request"
            content.body = "\(redemption.redeemedByName) wants \(redemption.rewardName)"
            content.sound = .default

            // The redemption's own id: the system then treats a re-post of
            // the same request as a replacement rather than a second banner.
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    /// XCUITest drives a real parent through a real redemption, so the
    /// permission alert appears mid-suite. XCUITest's default interruption
    /// handler dismisses it by tapping *Allow* -- which is the problem: from
    /// then on, real banners post over the app and can intercept the taps a
    /// test is trying to make.
    ///
    /// Only the prompt is suppressed, and only when the harness asks for it.
    /// The queue, both badges, and the dedupe bookkeeping all still run, so
    /// nothing a test asserts on is stubbed out.
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
            // The in-app queue and tab badge carry the feature on their own.
            return false
        default:
            return true
        }
    }

    private func setBadge(_ count: Int) {
        Task { try? await center.setBadgeCount(count) }
    }

    private static func announcedKey(_ householdId: String) -> String {
        "announcedPendingRedemptions.\(householdId)"
    }
}

extension PendingRedemptionNotifier: UNUserNotificationCenterDelegate {
    /// Without this iOS silently drops the banner whenever the app is in the
    /// foreground -- which is the case this feature fires in most often, a
    /// parent using the app when a child redeems something.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
