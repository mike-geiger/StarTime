import Charts
import SwiftUI

struct ProgressTabView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var choreStore: ChoreStore

    private var isParent: Bool { householdStore.profile?.role == .parent }

    var body: some View {
        NavigationStack {
            List {
                if isParent {
                    ForEach(childMembers, id: \.uid) { child in
                        Section(child.name) {
                            pointsChart(for: child.uid)
                            streakRows(for: child.uid)
                        }
                        Section("\(child.name) — History") {
                            pastRows(for: choreStore.pastCompletions(for: child.uid))
                        }
                    }
                    if childMembers.isEmpty {
                        Text("Invite a child from Settings to see progress.")
                            .foregroundStyle(.secondary)
                    }
                } else if let myUID = auth.user?.uid {
                    Section("This Week") {
                        pointsChart(for: myUID)
                    }
                    Section("Streaks") {
                        streakRows(for: myUID)
                    }
                    Section("History") {
                        pastRows(for: choreStore.pastCompletions(for: myUID))
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }

    private var childMembers: [(uid: String, name: String)] {
        guard let members = householdStore.household?.members else { return [] }
        return members
            .filter { $0.value.role == .child }
            .map { (uid: $0.key, name: $0.value.name) }
            .sorted { $0.name < $1.name }
    }

    private func pointsChart(for uid: String) -> some View {
        Chart(last7DaysPoints(for: uid), id: \.day) { entry in
            BarMark(
                x: .value("Day", entry.day, unit: .day),
                y: .value("Points", entry.points)
            )
            .foregroundStyle(.orange)
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .frame(height: 140)
        .padding(.vertical, 4)
    }

    private func last7DaysPoints(for uid: String) -> [(day: Date, points: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayString = ChoreService.dayString(day)
            // A reversed completion's points were debited back off the
            // balance, so it must not still show up here -- otherwise this
            // chart would diverge from what Rewards actually shows.
            let points = choreStore.completions
                .filter { $0.completedByUID == uid && $0.scheduledDate == dayString && !$0.isReversed }
                .reduce(0) { $0 + $1.pointsAwarded }
            return (day: day, points: points)
        }
    }

    @ViewBuilder
    private func streakRows(for uid: String) -> some View {
        let assignedChores = choreStore.chores.filter { $0.assignedToUID == uid }
        if assignedChores.isEmpty {
            Text("No chores yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(assignedChores) { chore in
                let streak = choreStore.streak(for: chore)
                HStack {
                    Image(systemName: chore.icon)
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    Text(chore.title)
                    Spacer()
                    if streak > 0 {
                        Label("\(streak)", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pastRows(for completions: [ChoreCompletion]) -> some View {
        if completions.isEmpty {
            Text("No completions yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(completions) { completion in
                pastCompletionRow(completion)
            }
        }
    }

    /// `pastCompletionRow-<id>` is set on this row's `HStack`, the same
    /// container-identifier caveat as `recurringChoreRow-<id>` in
    /// `ManageChoresView` — SwiftUI doesn't reliably surface a `List` row
    /// container's identifier to `app.otherElements`, so a UI test should
    /// query by visible text instead.
    private func pastCompletionRow(_ completion: ChoreCompletion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(completion.choreTitle)
                    .strikethrough(completion.isReversed)
                Text(relativeDateString(for: completion.completedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if completion.isReversed {
                    Label("Undone", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = completion.reversalNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            Spacer()

            Text("\(completion.pointsAwarded) pts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("pastCompletionRow-\(completion.id ?? "")")
    }

    private func relativeDateString(for date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ProgressTabView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
