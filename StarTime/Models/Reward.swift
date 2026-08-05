import Foundation

struct Reward: Identifiable, Codable, Equatable {
    var id: String?
    var name: String
    var icon: String
    var pointCost: Int
    var isActive: Bool
    var createdAt: Date?

    static let iconChoices = [
        "gamecontroller.fill", "tv.fill", "gift.fill", "dollarsign.circle.fill",
        "moon.stars.fill", "bicycle", "cart.fill", "star.fill",
        "heart.fill", "film.fill", "cup.and.saucer.fill", "party.popper"
    ]
}
