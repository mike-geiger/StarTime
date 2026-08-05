import Foundation

enum RewardServiceError: LocalizedError {
    case insufficientBalance(String)

    var errorDescription: String? {
        switch self {
        case .insufficientBalance(let message):
            return message
        }
    }
}

struct RewardService {
    private var api: APIClient { APIClient.shared }

    @MainActor
    func fetchRewards() async throws -> [Reward] {
        struct Response: Decodable { let rewards: [Reward] }
        return try await api.send("GET", "rewards", as: Response.self).rewards
    }

    @MainActor
    func fetchRedemptions() async throws -> [Redemption] {
        struct Response: Decodable { let redemptions: [Redemption] }
        return try await api.send("GET", "redemptions", as: Response.self).redemptions
    }

    /// Every household member's point balance, keyed by uid. Replaces
    /// summing the lifetime completion/redemption ledger client-side.
    @MainActor
    func fetchBalances() async throws -> [String: Int] {
        struct Response: Decodable { let balances: [String: Int] }
        return try await api.send("GET", "balances", as: Response.self).balances
    }

    @MainActor
    func saveReward(_ reward: Reward) async throws {
        if let id = reward.id {
            try await api.send("PUT", "rewards/\(id)", body: reward)
        } else {
            try await api.send("POST", "rewards", body: reward)
        }
    }

    @MainActor
    func deleteReward(rewardId: String) async throws {
        try await api.send("DELETE", "rewards/\(rewardId)")
    }

    /// Point cost is looked up server-side from the stored reward, so only
    /// the reward's id and who's redeeming it are sent.
    @MainActor
    func redeem(rewardId: String, redeemedByUID: String, redeemedByName: String) async throws {
        struct Body: Encodable {
            let rewardId: String
            let redeemedByUID: String
            let redeemedByName: String
        }
        do {
            try await api.send(
                "POST", "redemptions",
                body: Body(rewardId: rewardId, redeemedByUID: redeemedByUID, redeemedByName: redeemedByName)
            )
        } catch let error as APIError where error.statusCode == 409 {
            // The balance condition failed inside the transaction -- i.e.
            // not enough points, including the racing-redemption case the
            // old client-side check couldn't catch.
            throw RewardServiceError.insufficientBalance(
                error.message ?? "That's more points than you have saved up."
            )
        }
    }
}
