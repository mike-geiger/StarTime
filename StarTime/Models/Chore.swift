import FirebaseFirestore

struct Chore: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var title: String
    var icon: String
    var points: Int
    var recurrence: Recurrence
    var weeklyDays: [Int]
    var assignedToUID: String
    var isActive: Bool
    @ServerTimestamp var createdAt: Date?

    enum Recurrence: String, Codable, CaseIterable {
        case once
        case daily
        case weekly

        var label: String {
            switch self {
            case .once: return "One time"
            case .daily: return "Every day"
            case .weekly: return "Certain days"
            }
        }
    }

    static let iconChoices = [
        "sparkles", "bed.double.fill", "fork.knife", "pawprint.fill",
        "book.fill", "washer.fill", "trash.fill", "leaf.fill",
        "car.fill", "backpack.fill", "paintbrush.fill", "house.fill"
    ]
}
