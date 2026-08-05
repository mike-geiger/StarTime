import Combine
import Foundation

@MainActor
final class RewardStore: ObservableObject {
    @Published private(set) var rewards: [Reward] = []
    @Published private(set) var redemptions: [Redemption] = []
    /// Server-maintained point balances keyed by uid. The all-time
    /// `completions` array this store used to hold existed only to compute
    /// these, so it's gone entirely rather than refactored.
    @Published private(set) var balances: [String: Int] = [:]
    @Published var errorMessage: String?

    private let service = RewardService()
    private var householdId: String?
    private var invalidationSubscription: AnyCancellable?

    func start(householdId: String) {
        guard self.householdId != householdId else { return }
        stop()
        self.householdId = householdId
        refresh()
    }

    func stop() {
        // See ChoreStore.stop(): the invalidation subscription deliberately
        // survives, because `start()` calls `stop()` and clearing it here
        // unsubscribed the store from every push.
        householdId = nil
        rewards = []
        redemptions = []
        balances = [:]
    }

    /// Balances are included deliberately: completing a chore over in the
    /// Chores tab credits points, and the stream reports that as a
    /// `balances` change — which is what the interim cross-store callback
    /// used to cover.
    func observe(_ realtime: RealtimeConnectionManager) {
        invalidationSubscription = realtime.invalidations
            .filter { $0.contains(.rewards) || $0.contains(.redemptions) || $0.contains(.balances) }
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard householdId != nil else { return }
        Task {
            do {
                async let rewards = service.fetchRewards()
                async let redemptions = service.fetchRedemptions()
                async let balances = service.fetchBalances()
                self.rewards = try await rewards
                self.redemptions = try await redemptions
                self.balances = try await balances
            } catch {
                // Deliberately not surfaced: a background refetch can fail
                // transiently (e.g. mid sign-out, when the profile read
                // 404s), and turning that into a modal alert would block
                // the UI for something the next refresh fixes on its own.
                // Only user-initiated actions populate `errorMessage`.
                print("RewardStore refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func balance(for uid: String) -> Int {
        balances[uid] ?? 0
    }

    func redemptions(for uid: String) -> [Redemption] {
        redemptions
            .filter { $0.redeemedByUID == uid }
            .sorted { ($0.redeemedAt ?? .distantPast) > ($1.redeemedAt ?? .distantPast) }
    }

    /// No local balance pre-check any more: the server's conditional
    /// transaction is the only thing that can decide affordability without
    /// racing. `canAfford` in the UI still gates the button for a sensible
    /// default state, but a stale local balance can no longer overdraw.
    func redeem(_ reward: Reward, forUID uid: String, name: String) {
        guard let rewardId = reward.id else { return }
        perform { try await self.service.redeem(rewardId: rewardId, redeemedByUID: uid, redeemedByName: name) }
    }

    func addReward(_ reward: Reward) {
        perform { try await self.service.saveReward(reward) }
    }

    func updateReward(_ reward: Reward) {
        perform { try await self.service.saveReward(reward) }
    }

    func deleteReward(_ reward: Reward) {
        guard let rewardId = reward.id else { return }
        perform { try await self.service.deleteReward(rewardId: rewardId) }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
