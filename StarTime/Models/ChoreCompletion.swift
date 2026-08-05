import Foundation

struct ChoreCompletion: Identifiable, Codable {
    var id: String?
    var choreId: String
    var choreTitle: String
    var pointsAwarded: Int
    var completedByUID: String
    var completedByName: String
    var completedAt: Date?
    /// "yyyy-MM-dd" — the calendar day this completion counts toward, used
    /// for streaks and to prevent completing the same chore twice in a day.
    var scheduledDate: String
}
