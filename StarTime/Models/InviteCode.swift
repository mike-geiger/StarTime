import FirebaseFirestore

/// Document ID is the 6-character code itself, e.g. "K7QX2M".
struct InviteCode: Codable {
    var householdId: String
    var role: Household.Role
    var createdByUID: String
    @ServerTimestamp var createdAt: Date?
}
