import FirebaseFirestore

struct Redemption: Identifiable, Codable {
    @DocumentID var id: String?
    var rewardId: String
    var rewardName: String
    var pointsSpent: Int
    var redeemedByUID: String
    var redeemedByName: String
    @ServerTimestamp var redeemedAt: Date?
}
