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

    @MainActor
    func recordCompletion(_ completion: ChoreCompletion) async throws {
        try await api.send("POST", "completions", body: completion)
    }
}
