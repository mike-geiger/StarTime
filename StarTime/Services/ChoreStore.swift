import Combine
import Foundation

@MainActor
final class ChoreStore: ObservableObject {
    @Published private(set) var chores: [Chore] = []
    @Published private(set) var completions: [ChoreCompletion] = []
    /// Chore ids with a completion request in flight. `isCompletedToday` only
    /// flips once the write lands *and* the refetch returns, which leaves a
    /// few hundred milliseconds where the button is still tappable — long
    /// enough to double-credit a chore with one impatient double-tap.
    @Published private(set) var pendingCompletions: Set<String> = []
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
        // Deliberately does NOT drop `invalidationSubscription`: `start()`
        // calls `stop()` as its reset step, so clearing it here silently
        // unsubscribed whatever `observe()` had just set up, and no pushed
        // invalidation ever reached this store. The subscription outlives
        // the household lifecycle; `refresh()` no-ops when householdId is
        // nil, so a late invalidation is harmless.
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
    /// on start, after every mutation, and whenever the server pushes an
    /// invalidation for a collection this store owns.
    func refresh() {
        Task { await refreshNow() }
    }

    /// The awaitable form, so a caller that must not finish before the fresh
    /// data lands (see `complete`) can wait for it.
    func refreshNow() async {
        guard householdId != nil else { return }
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

    /// Daily/weekly chores assigned to `uid` (or all assignees), regardless
    /// of whether they're due today — for the "Recurring" section.
    func recurringChores(for uid: String? = nil) -> [Chore] {
        chores
            .filter { chore in
                if let uid, chore.assignedToUID != uid { return false }
                return chore.recurrence != .once
            }
            .sorted { $0.title < $1.title }
    }

    /// Completion history for `uid` (or all assignees), most recent first —
    /// for the "Past" section.
    func pastCompletions(for uid: String? = nil) -> [ChoreCompletion] {
        completions
            .filter { completion in
                guard let uid else { return true }
                return completion.completedByUID == uid
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
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

    /// True from the moment Complete is tapped until the refetch settles.
    func isCompleting(_ chore: Chore) -> Bool {
        guard let id = chore.id else { return false }
        return pendingCompletions.contains(id)
    }

    func complete(_ chore: Chore, assigneeName: String) {
        guard let choreId = chore.id else { return }
        guard !pendingCompletions.contains(choreId) else { return }
        pendingCompletions.insert(choreId)
        let completion = ChoreCompletion(
            choreId: choreId,
            choreTitle: chore.title,
            pointsAwarded: chore.points,
            completedByUID: chore.assignedToUID,
            completedByName: assigneeName,
            scheduledDate: ChoreService.dayString(Date())
        )
        perform(
            { try await self.service.recordCompletion(completion) },
            // Held until after the refetch, so the button never flickers back
            // to tappable in the gap between the write and the fresh data.
            always: { self.pendingCompletions.remove(choreId) }
        )
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
    private func perform(
        _ work: @escaping () async throws -> Void,
        always cleanup: (() -> Void)? = nil
    ) {
        Task {
            do {
                try await work()
                await refreshNow()
            } catch {
                errorMessage = error.localizedDescription
            }
            cleanup?()
        }
    }
}
