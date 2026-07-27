import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class RewardStore: ObservableObject {
    @Published private(set) var rewards: [Reward] = []
    @Published private(set) var completions: [ChoreCompletion] = []
    @Published private(set) var redemptions: [Redemption] = []
    @Published var errorMessage: String?

    private let service = RewardService()
    private var rewardsListener: ListenerRegistration?
    private var completionsListener: ListenerRegistration?
    private var redemptionsListener: ListenerRegistration?
    private var householdId: String?

    func start(householdId: String) {
        guard self.householdId != householdId else { return }
        stop()
        self.householdId = householdId

        rewardsListener = service.rewardsListener(householdId: householdId) { [weak self] in self?.rewards = $0 }
        completionsListener = service.completionsListener(householdId: householdId) { [weak self] in self?.completions = $0 }
        redemptionsListener = service.redemptionsListener(householdId: householdId) { [weak self] in self?.redemptions = $0 }
    }

    func stop() {
        rewardsListener?.remove()
        completionsListener?.remove()
        redemptionsListener?.remove()
        rewardsListener = nil
        completionsListener = nil
        redemptionsListener = nil
        householdId = nil
        rewards = []
        completions = []
        redemptions = []
    }

    func balance(for uid: String) -> Int {
        let earned = completions.filter { $0.completedByUID == uid }.reduce(0) { $0 + $1.pointsAwarded }
        let spent = redemptions.filter { $0.redeemedByUID == uid }.reduce(0) { $0 + $1.pointsSpent }
        return earned - spent
    }

    func redemptions(for uid: String) -> [Redemption] {
        redemptions
            .filter { $0.redeemedByUID == uid }
            .sorted { ($0.redeemedAt ?? .distantPast) > ($1.redeemedAt ?? .distantPast) }
    }

    func redeem(_ reward: Reward, forUID uid: String, name: String) {
        guard let householdId, let rewardId = reward.id else { return }
        guard balance(for: uid) >= reward.pointCost else { return }
        let redemption = Redemption(
            rewardId: rewardId,
            rewardName: reward.name,
            pointsSpent: reward.pointCost,
            redeemedByUID: uid,
            redeemedByName: name
        )
        do {
            try service.recordRedemption(householdId: householdId, redemption: redemption)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addReward(_ reward: Reward) {
        guard let householdId else { return }
        do {
            try service.addReward(householdId: householdId, reward: reward)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateReward(_ reward: Reward) {
        guard let householdId else { return }
        do {
            try service.updateReward(householdId: householdId, reward: reward)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteReward(_ reward: Reward) {
        guard let householdId, let rewardId = reward.id else { return }
        Task {
            do {
                try await service.deleteReward(householdId: householdId, rewardId: rewardId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
