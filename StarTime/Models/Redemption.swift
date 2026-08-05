import Foundation

struct Redemption: Identifiable, Codable {
    var id: String?
    var rewardId: String
    var rewardName: String
    var pointsSpent: Int
    var redeemedByUID: String
    var redeemedByName: String
    var redeemedAt: Date?
}
