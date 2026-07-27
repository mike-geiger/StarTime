import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class ChoreStore: ObservableObject {
    @Published private(set) var chores: [Chore] = []
    @Published private(set) var completions: [ChoreCompletion] = []
    @Published var errorMessage: String?

    private let service = ChoreService()
    private var choresListener: ListenerRegistration?
    private var completionsListener: ListenerRegistration?
    private var householdId: String?

    func start(householdId: String) {
        guard self.householdId != householdId else { return }
        stop()
        self.householdId = householdId

        choresListener = service.choresListener(householdId: householdId) { [weak self] chores in
            self?.chores = chores
        }

        // 60 days back is plenty of history for any realistic streak.
        let since = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? .distantPast
        completionsListener = service.completionsListener(householdId: householdId, since: since) { [weak self] completions in
            self?.completions = completions
        }
    }

    func stop() {
        choresListener?.remove()
        completionsListener?.remove()
        choresListener = nil
        completionsListener = nil
        householdId = nil
        chores = []
        completions = []
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
        guard let householdId, let choreId = chore.id else { return }
        let completion = ChoreCompletion(
            choreId: choreId,
            choreTitle: chore.title,
            pointsAwarded: chore.points,
            completedByUID: chore.assignedToUID,
            completedByName: assigneeName,
            scheduledDate: ChoreService.dayString(Date())
        )
        do {
            try service.recordCompletion(householdId: householdId, completion: completion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addChore(_ chore: Chore) {
        guard let householdId else { return }
        do {
            try service.addChore(householdId: householdId, chore: chore)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateChore(_ chore: Chore) {
        guard let householdId else { return }
        do {
            try service.updateChore(householdId: householdId, chore: chore)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteChore(_ chore: Chore) {
        guard let householdId, let choreId = chore.id else { return }
        Task {
            do {
                try await service.deleteChore(householdId: householdId, choreId: choreId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
