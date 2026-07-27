import FirebaseFirestore

struct Household: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var members: [String: Member]
    var lastJoinCode: String?
    @ServerTimestamp var createdAt: Date?

    struct Member: Codable {
        var name: String
        var role: Role
    }

    enum Role: String, Codable {
        case parent
        case child
    }
}
