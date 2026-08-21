import Foundation

struct Chore: Identifiable, Codable, Equatable {
    var id: String?
    var title: String
    var icon: String
    var points: Int
    var recurrence: Recurrence
    var weeklyDays: [Int]
    var assignedToUID: String
    var isActive: Bool
    /// Gates this chore's completion: with items, it completes only once
    /// every item is checked, instead of a single tap. The server always
    /// includes this field (defaulting a legacy chore with none to `[]`),
    /// so it decodes as a plain array rather than optional.
    var items: [ChecklistItem]
    var createdAt: Date?

    /// A single gate on a checklist chore's completion. Carries no point
    /// value of its own -- only the whole chore's completion credits
    /// points.
    struct ChecklistItem: Identifiable, Codable, Equatable {
        var id: String
        var title: String
    }

    /// True when this chore completes via a checklist rather than a
    /// single tap.
    var isChecklist: Bool { !items.isEmpty }

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

    /// Human-readable recurrence schedule ("Daily", "Mon, Wed, Fri"). Not
    /// meaningful for `.once` chores, which aren't recurring.
    var scheduleDescription: String {
        switch recurrence {
        case .once:
            return ""
        case .daily:
            return "Daily"
        case .weekly:
            // Calendar's weekday symbol arrays are always Sunday-first
            // (index 0 = Sunday), matching the 0 = Sunday convention used
            // for `weeklyDays` elsewhere (see ChoreStore.choresDueToday).
            let symbols = Calendar.current.shortWeekdaySymbols
            return weeklyDays.sorted()
                .compactMap { symbols.indices.contains($0) ? symbols[$0] : nil }
                .joined(separator: ", ")
        }
    }
}
