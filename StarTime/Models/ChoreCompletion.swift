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
    /// Set when a checklist chore's completion was later undone by
    /// unchecking an item. The entry itself is never deleted or rewritten —
    /// these are the only fields ever added after creation.
    var reversedAt: Date?
    var reversedByUID: String?
    var reversalNote: String?

    var isReversed: Bool { reversedAt != nil }
}
