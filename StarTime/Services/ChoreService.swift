import Foundation

struct ChoreService {
    private var api: APIClient { APIClient.shared }

    /// Canonical formatter for `ChoreCompletion.scheduledDate`. Completions
    /// are matched by exact string equality on this field (streaks, "already
    /// done today"), so nothing may format that date ad hoc.
    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    @MainActor
    func fetchChores() async throws -> [Chore] {
        struct Response: Decodable { let chores: [Chore] }
        return try await api.send("GET", "chores", as: Response.self).chores
    }

    /// `since` is an ISO8601 instant; omitting it returns the full history.
    @MainActor
    func fetchCompletions(since: Date?) async throws -> [ChoreCompletion] {
        struct Response: Decodable { let completions: [ChoreCompletion] }
        var path = "completions"
        if let since {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let encoded = formatter.string(from: since)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            path += "?since=\(encoded)"
        }
        return try await api.send("GET", path, as: Response.self).completions
    }

    @MainActor
    func saveChore(_ chore: Chore) async throws {
        if let id = chore.id {
            try await api.send("PUT", "chores/\(id)", body: chore)
        } else {
            try await api.send("POST", "chores", body: chore)
        }
    }

    @MainActor
    func deleteChore(choreId: String) async throws {
        try await api.send("DELETE", "chores/\(choreId)")
    }

    /// Returns false if the server rejected the completion as already done
    /// today (409) — a benign race, not an error worth showing: another tap
    /// or another device got there first, and a refetch shows the truth.
    @MainActor
    @discardableResult
    func recordCompletion(_ completion: ChoreCompletion) async throws -> Bool {
        do {
            try await api.send("POST", "completions", body: completion)
            return true
        } catch let error as APIError where error.statusCode == 409 {
            return false
        }
    }

    /// Every checklist chore's checked items for one day, across the
    /// household — needed so a fresh launch or a second device can render
    /// checkboxes reflecting what's already checked.
    @MainActor
    func fetchChecklistProgress(scheduledDate: String) async throws -> [ChoreChecklistProgress] {
        struct Response: Decodable { let checklists: [ChoreChecklistProgress] }
        return try await api.send("GET", "chores/checklist?scheduledDate=\(scheduledDate)", as: Response.self).checklists
    }

    /// Checks one item. The server credits the chore's points, exactly
    /// once, if this happens to be the item that completes the set — see
    /// design.md for why that's safe under concurrent checks.
    @MainActor
    func checkChecklistItem(choreId: String, itemId: String, scheduledDate: String) async throws {
        try await api.send("POST", "chores/\(choreId)/checklist/items/\(itemId)/check?scheduledDate=\(scheduledDate)")
    }

    /// Unchecks one item. Any household member may do this, including the
    /// assignee themselves. If the chore had already completed today, this
    /// reverses it — the points are debited back in full, uncapped.
    @MainActor
    func uncheckChecklistItem(choreId: String, itemId: String, scheduledDate: String, note: String?) async throws {
        struct Body: Encodable { let note: String? }
        try await api.send(
            "POST",
            "chores/\(choreId)/checklist/items/\(itemId)/uncheck?scheduledDate=\(scheduledDate)",
            body: Body(note: note)
        )
    }

    /// Explicitly completes a checklist chore whose checked items already
    /// satisfy every currently-required item — the case where editing the
    /// item list left nothing left to check, so there's no item tap to
    /// trigger completion on its own.
    @MainActor
    func completeChecklist(choreId: String, scheduledDate: String) async throws {
        try await api.send("POST", "chores/\(choreId)/checklist/complete?scheduledDate=\(scheduledDate)")
    }
}
