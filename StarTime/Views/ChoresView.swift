import SwiftUI

struct ChoresView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var choreStore: ChoreStore

    @State private var showingAddChore = false
    @State private var editingChore: Chore?

    private var isParent: Bool { householdStore.profile?.role == .parent }

    var body: some View {
        NavigationStack {
            List {
                if isParent {
                    ForEach(childMembers, id: \.uid) { child in
                        assigneeSections(for: child.uid, name: child.name)
                    }
                    if childMembers.isEmpty {
                        Text("Invite a child from Settings to start assigning chores.")
                            .foregroundStyle(.secondary)
                    }
                } else if let myUID = auth.user?.uid {
                    assigneeSections(for: myUID, name: householdStore.profile?.name ?? "My")
                }
            }
            .navigationTitle("Chores")
            .toolbar {
                if isParent {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddChore = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showingAddChore) {
                AddEditChoreView(choreStore: choreStore, household: householdStore.household)
            }
            .sheet(item: $editingChore) { chore in
                AddEditChoreView(choreStore: choreStore, household: householdStore.household, editingChore: chore)
            }
        }
    }

    @ViewBuilder
    private func assigneeSections(for uid: String, name: String) -> some View {
        Section("\(name) — Active") {
            choreRows(for: choreStore.choresDueToday(for: uid))
        }
        Section("\(name) — Recurring") {
            recurringRows(for: choreStore.recurringChores(for: uid))
        }
        Section("\(name) — Past") {
            pastRows(for: choreStore.pastCompletions(for: uid))
        }
    }

    @ViewBuilder
    private func choreRows(for chores: [Chore]) -> some View {
        if chores.isEmpty {
            Text("Nothing due today 🎉")
                .foregroundStyle(.secondary)
        } else {
            ForEach(chores) { chore in
                choreRow(chore)
            }
        }
    }

    @ViewBuilder
    private func recurringRows(for chores: [Chore]) -> some View {
        if chores.isEmpty {
            Text("No recurring chores yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(chores) { chore in
                recurringChoreRow(chore)
            }
        }
    }

    /// `recurringChoreRow-<id>` is set on this row's `HStack`, the same
    /// pattern `pendingRedemptionRow-<id>` uses in RewardsView — SwiftUI
    /// doesn't reliably surface a `List` row container's identifier to
    /// `app.otherElements`, so a future UI test should query by visible
    /// text instead (see `StarTimeUITests.queuedRequest`).
    private func recurringChoreRow(_ chore: Chore) -> some View {
        HStack {
            Image(systemName: chore.icon)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                Text(chore.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(chore.points) pts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("recurringChoreRow-\(chore.id ?? "")")
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

    /// `pastCompletionRow-<id>` has the same container-identifier caveat as
    /// `recurringChoreRow-<id>` above.
    private func pastCompletionRow(_ completion: ChoreCompletion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(completion.choreTitle)
                Text(relativeDateString(for: completion.completedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var childMembers: [(uid: String, name: String)] {
        guard let members = householdStore.household?.members else { return [] }
        return members
            .filter { $0.value.role == .child }
            .map { (uid: $0.key, name: $0.value.name) }
            .sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private func choreRow(_ chore: Chore) -> some View {
        let done = choreStore.isCompletedToday(chore)
        let streak = choreStore.streak(for: chore)

        HStack {
            Image(systemName: chore.icon)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                    .strikethrough(done)
                HStack(spacing: 6) {
                    Text("\(chore.points) pts")
                    if streak > 0 {
                        Label("\(streak)", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                complete(chore)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(done || choreStore.isCompleting(chore))
            .accessibilityIdentifier("completeChoreButton-\(chore.id ?? "")")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isParent { editingChore = chore }
        }
        .swipeActions {
            if isParent {
                Button("Delete", role: .destructive) { choreStore.deleteChore(chore) }
            }
        }
    }

    private func complete(_ chore: Chore) {
        let name = householdStore.household?.members[chore.assignedToUID]?.name ?? "Someone"
        choreStore.complete(chore, assigneeName: name)
    }
}

#Preview {
    ChoresView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
