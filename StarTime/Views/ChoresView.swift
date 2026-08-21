import SwiftUI

struct ChoresView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var choreStore: ChoreStore

    @State private var showingAddChore = false
    @State private var editingChore: Chore?
    /// Unchecking an item on an already-completed checklist is a reversal —
    /// it takes back the points, so it asks first, the same shape
    /// RewardsView uses for cancel/un-fulfil.
    @State private var pendingChecklistReversal: PendingChecklistReversal?
    @State private var checklistReversalNoteDraft = ""

    private struct PendingChecklistReversal {
        let chore: Chore
        let item: Chore.ChecklistItem
    }

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
        // Chore mutations (add/edit/delete/check/uncheck) had no error
        // surfacing at all -- a failed save dismissed its sheet exactly
        // like a successful one, silently discarding the attempted change.
        // Mirrors RewardsView's identical alert for RewardStore.
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { choreStore.errorMessage != nil },
                set: { if !$0 { choreStore.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { choreStore.errorMessage = nil }
        } message: {
            Text(choreStore.errorMessage ?? "")
        }
        // `.confirmationDialog` can't host a `TextField`, so the optional
        // note pushes this to `.alert`, mirroring RewardsView's cancel and
        // un-fulfil confirmations.
        .alert(
            "Undo this item?",
            isPresented: Binding(
                get: { pendingChecklistReversal != nil },
                set: { if !$0 { pendingChecklistReversal = nil; checklistReversalNoteDraft = "" } }
            ),
            presenting: pendingChecklistReversal
        ) { pending in
            TextField("Note (optional)", text: $checklistReversalNoteDraft)
            Button("Undo and take back \(pending.chore.points) points", role: .destructive) {
                let trimmed = checklistReversalNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                choreStore.uncheckItem(pending.chore, itemId: pending.item.id, note: trimmed.isEmpty ? nil : trimmed)
                pendingChecklistReversal = nil
                checklistReversalNoteDraft = ""
            }
            Button("Keep it done", role: .cancel) {
                pendingChecklistReversal = nil
                checklistReversalNoteDraft = ""
            }
        } message: { pending in
            Text("\"\(pending.item.title)\" will be unchecked, and \(pending.chore.points) points will be taken back.")
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

    private var childMembers: [(uid: String, name: String)] {
        guard let members = householdStore.household?.members else { return [] }
        return members
            .filter { $0.value.role == .child }
            .map { (uid: $0.key, name: $0.value.name) }
            .sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private func choreRow(_ chore: Chore) -> some View {
        if chore.isChecklist {
            checklistChoreRow(chore)
        } else {
            simpleChoreRow(chore)
        }
    }

    @ViewBuilder
    private func simpleChoreRow(_ chore: Chore) -> some View {
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

    @ViewBuilder
    private func checklistChoreRow(_ chore: Chore) -> some View {
        let done = choreStore.isCompletedToday(chore)
        let streak = choreStore.streak(for: chore)
        let checkedCount = chore.items.filter { choreStore.isChecklistItemChecked(chore, itemId: $0.id) }.count

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: chore.icon)
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chore.title)
                        .strikethrough(done)
                    HStack(spacing: 6) {
                        Text("\(chore.points) pts")
                        Text("\(checkedCount)/\(chore.items.count)")
                        if streak > 0 {
                            Label("\(streak)", systemImage: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isParent { editingChore = chore }
            }

            ForEach(chore.items) { item in
                checklistItemRow(chore, item: item)
            }

            if choreStore.isChecklistAwaitingExplicitCompletion(chore) {
                Button("Mark Complete") {
                    choreStore.markChecklistComplete(chore)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("markChecklistCompleteButton-\(chore.id ?? "")")
            }
        }
        .swipeActions {
            if isParent {
                Button("Delete", role: .destructive) { choreStore.deleteChore(chore) }
            }
        }
    }

    private func checklistItemRow(_ chore: Chore, item: Chore.ChecklistItem) -> some View {
        let checked = choreStore.isChecklistItemChecked(chore, itemId: item.id)

        return Button {
            toggleChecklistItem(chore, item: item, checked: checked)
        } label: {
            HStack {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? .green : .secondary)
                Text(item.title)
                    .strikethrough(checked)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 28)
        .accessibilityIdentifier("checklistItemCheckbox-\(chore.id ?? "")-\(item.id)")
    }

    /// Checking is always safe to do directly. Unchecking is too, unless
    /// the chore already completed today — then it's a reversal that takes
    /// points back, so it's confirmed first (see the alert in `body`).
    private func toggleChecklistItem(_ chore: Chore, item: Chore.ChecklistItem, checked: Bool) {
        guard checked else {
            choreStore.checkItem(chore, itemId: item.id)
            return
        }
        if choreStore.isCompletedToday(chore) {
            pendingChecklistReversal = PendingChecklistReversal(chore: chore, item: item)
        } else {
            choreStore.uncheckItem(chore, itemId: item.id)
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
