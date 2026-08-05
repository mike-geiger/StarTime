import Foundation

/// One item per signed-in user at `USER#{uid}` / `PROFILE`. Exists so the app
/// can find "my household" with a single cheap read instead of scanning every
/// household's member map.
struct UserProfile: Codable {
    var name: String
    var householdId: String?
    var role: Household.Role?
}
