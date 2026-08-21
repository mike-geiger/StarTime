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
}

#Preview {
    ProgressTabView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
