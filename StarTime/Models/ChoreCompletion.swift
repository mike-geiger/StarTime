import FirebaseFirestore

struct ChoreCompletion: Identifiable, Codable {
    @DocumentID var id: String?
    var choreId: String
    var choreTitle: String
    var pointsAwarded: Int
    var completedByUID: String
    var completedByName: String
    @ServerTimestamp var completedAt: Date?
    /// "yyyy-MM-dd" — the calendar day this completion counts toward, used
    /// for streaks and to prevent completing the same chore twice in a day.
    var scheduledDate: String
}
