import Combine
import Foundation

@MainActor
final class ChoreStore: ObservableObject {
    @Published private(set) var chores: [Chore] = []
    @Published private(set) var completions: [ChoreCompletion] = []
    @Published var errorMessage: String?

    private let service = ChoreService()
    private var householdId: String?
    private var invalidationSubscription: AnyCancellable?

    /// `householdId` is no longer passed to the backend (handlers derive it
    /// from the caller's token) — it's kept as the change token that tells
    /// this store when it's looking at a different household.
    func start(householdId: String) {
        guard self.householdId != householdId else { return }
        stop()
        self.householdId = householdId
        refresh()
    }

    func stop() {
        invalidationSubscription = nil
        householdId = nil
        chores = []
        completions = []
    }

    /// Refetch when the server says these collections changed elsewhere —
    /// another family member's device, or this one's own writes coming back
    /// around. Replaces the Firestore snapshot listeners.
    func observe(_ realtime: RealtimeConnectionManager) {
        invalidationSubscription = realtime.invalidations
            .filter { $0.contains(.chores) || $0.contains(.completions) }
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Replaces what the two Firestore snapshot listeners used to do. Called
    /// on start and after every mutation; Phase 5 adds a WebSocket
    /// invalidation signal that calls this on remote changes too.
    func refresh() {
        guard householdId != nil else { return }
        Task {
            do {
                async let chores = service.fetchChores()
                // 60 days back is plenty of history for any realistic streak.
                let since = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? .distantPast
                async let completions = service.fetchCompletions(since: since)
                self.chores = try await chores
                self.completions = try await completions
            } catch {
                // Same as RewardStore.refresh: background refetch failures
                // are transient and self-correcting, so they don't get
                // surfaced as user-facing errors.
                print("ChoreStore refresh failed: \(error.localizedDescription)")
            }
        }
    }

    /// Chores due today, optionally restricted to one assignee.
    func choresDueToday(for uid: String? = nil) -> [Chore] {
        let todayWeekday = Calendar.current.component(.weekday, from: Date()) - 1 // 0 = Sunday
        return chores.filter { chore in
            if let uid, chore.assignedToUID != uid { return false }
            switch chore.recurrence {
            case .once:
                return !completions.contains { $0.choreId == chore.id }
            case .daily:
                return true
            case .weekly:
                return chore.weeklyDays.contains(todayWeekday)
            }
        }
    }

    func isCompletedToday(_ chore: Chore) -> Bool {
        let today = ChoreService.dayString(Date())
        return completions.contains { $0.choreId == chore.id && $0.scheduledDate == today }
    }

    /// Consecutive days (or, for weekly chores, consecutive due-days) this
    /// chore has been completed, walking back from today.
    func streak(for chore: Chore) -> Int {
        guard let choreId = chore.id else { return 0 }
        let calendar = Calendar.current
        let completedDays = Set(completions.filter { $0.choreId == choreId }.map(\.scheduledDate))

        var streak = 0
        var cursor = Date()
        if !completedDays.contains(ChoreService.dayString(cursor)) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        while true {
            let weekday = calendar.component(.weekday, from: cursor) - 1
            if chore.recurrence == .weekly && !chore.weeklyDays.contains(weekday) {
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                continue
            }
            guard completedDays.contains(ChoreService.dayString(cursor)) else { break }
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    func complete(_ chore: Chore, assigneeName: String) {
        guard let choreId = chore.id else { return }
        let completion = ChoreCompletion(
            choreId: choreId,
            choreTitle: chore.title,
            pointsAwarded: chore.points,
            completedByUID: chore.assignedToUID,
            completedByName: assigneeName,
            scheduledDate: ChoreService.dayString(Date())
        )
        perform { try await self.service.recordCompletion(completion) }
    }

    func addChore(_ chore: Chore) {
        perform { try await self.service.saveChore(chore) }
    }

    func updateChore(_ chore: Chore) {
        perform { try await self.service.saveChore(chore) }
    }

    func deleteChore(_ chore: Chore) {
        guard let choreId = chore.id else { return }
        perform { try await self.service.deleteChore(choreId: choreId) }
    }

    /// Runs a mutation, then refetches — without a live listener, a write
    /// isn't visible until we read it back.
    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
