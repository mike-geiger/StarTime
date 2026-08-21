import SwiftUI

struct ManageChoresView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var choreStore: ChoreStore

    @State private var editingChore: Chore?

    private var isParent: Bool { householdStore.profile?.role == .parent }

    var body: some View {
        NavigationStack {
            List {
                if isParent {
                    ForEach(childMembers, id: \.uid) { child in
                        Section(child.name) {
                            recurringRows(for: choreStore.recurringChores(for: child.uid))
                        }
                    }
                    if childMembers.isEmpty {
                        Text("Invite a child from Settings to start assigning chores.")
                            .foregroundStyle(.secondary)
                    }
                } else if let myUID = auth.user?.uid {
                    Section("Recurring") {
                        recurringRows(for: choreStore.recurringChores(for: myUID))
                    }
                }
            }
            .navigationTitle("Manage Chores")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingChore) { chore in
                AddEditChoreView(choreStore: choreStore, household: householdStore.household, editingChore: chore)
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
    /// `app.otherElements`, so a UI test should query by visible text
    /// instead (see `StarTimeUITests.queuedRequest`).
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

    private var childMembers: [(uid: String, name: String)] {
        guard let members = householdStore.household?.members else { return [] }
        return members
            .filter { $0.value.role == .child }
            .map { (uid: $0.key, name: $0.value.name) }
            .sorted { $0.name < $1.name }
    }
}

#Preview {
    ManageChoresView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
