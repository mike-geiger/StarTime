import FirebaseFirestore

/// One document per signed-in user at `users/{uid}`. Exists so the app can
/// find "my household" with a single cheap document read instead of a
/// collection query over every household's member map.
struct UserProfile: Codable {
    var name: String
    var householdId: String?
    var role: Household.Role?
}
