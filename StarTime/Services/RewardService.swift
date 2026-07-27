import FirebaseFirestore

struct RewardService {
    private let db = Firestore.firestore()

    func rewardsListener(householdId: String, onChange: @escaping ([Reward]) -> Void) -> ListenerRegistration {
        db.collection("households").document(householdId).collection("rewards")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { snapshot, _ in
                onChange(snapshot?.documents.compactMap { try? $0.data(as: Reward.self) } ?? [])
            }
    }

    /// All-time completions (no start-date cutoff, unlike the streak-focused
    /// listener in ChoreService) since point balances are cumulative for life.
    func completionsListener(householdId: String, onChange: @escaping ([ChoreCompletion]) -> Void) -> ListenerRegistration {
        db.collection("households").document(householdId).collection("completions")
            .addSnapshotListener { snapshot, _ in
                onChange(snapshot?.documents.compactMap { try? $0.data(as: ChoreCompletion.self) } ?? [])
            }
    }

    func redemptionsListener(householdId: String, onChange: @escaping ([Redemption]) -> Void) -> ListenerRegistration {
        db.collection("households").document(householdId).collection("redemptions")
            .addSnapshotListener { snapshot, _ in
                onChange(snapshot?.documents.compactMap { try? $0.data(as: Redemption.self) } ?? [])
            }
    }

    func addReward(householdId: String, reward: Reward) throws {
        let ref = db.collection("households").document(householdId).collection("rewards").document()
        try ref.setData(from: reward)
    }

    func updateReward(householdId: String, reward: Reward) throws {
        guard let rewardId = reward.id else { return }
        try db.collection("households").document(householdId).collection("rewards").document(rewardId).setData(from: reward)
    }

    func deleteReward(householdId: String, rewardId: String) async throws {
        try await db.collection("households").document(householdId).collection("rewards").document(rewardId).delete()
    }

    func recordRedemption(householdId: String, redemption: Redemption) throws {
        let ref = db.collection("households").document(householdId).collection("redemptions").document()
        try ref.setData(from: redemption)
    }
}
