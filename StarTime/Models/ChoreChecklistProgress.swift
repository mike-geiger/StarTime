import Foundation

/// One checklist chore's checked items for a single day. Distinct from
/// `ChoreCompletion` — this is in-progress state, not the completion event
/// itself. Whether the day is done is still decided solely by whether a
/// non-reversed `ChoreCompletion` exists for it.
struct ChoreChecklistProgress: Codable {
    var choreId: String
    var scheduledDate: String
    var checkedItemIds: [String]
}
