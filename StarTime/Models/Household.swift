import Foundation

struct Household: Identifiable, Codable {
    var id: String
    var name: String
    var members: [String: Member]
    var lastJoinCode: String?
    var createdAt: Date?

    struct Member: Codable {
        var name: String
        var role: Role
    }

    enum Role: String, Codable {
        case parent
        case child
    }
}
