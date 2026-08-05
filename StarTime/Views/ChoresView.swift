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
                        Section(child.name) {
                            choreRows(for: choreStore.choresDueToday(for: child.uid))
                        }
                    }
                    if childMembers.isEmpty {
                        Text("Invite a child from Settings to start assigning chores.")
                            .foregroundStyle(.secondary)
                    }
                } else if let myUID = auth.user?.uid {
                    choreRows(for: choreStore.choresDueToday(for: myUID))
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
            .disabled(done)
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
