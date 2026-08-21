import SwiftUI

struct AddEditChoreView: View {
    @Environment(\.dismiss) private var dismiss

    var choreStore: ChoreStore
    var household: Household?
    var editingChore: Chore?

    @State private var title = ""
    @State private var points = 5
    @State private var icon = Chore.iconChoices[0]
    @State private var recurrence: Chore.Recurrence = .daily
    @State private var weeklyDays: Set<Int> = []
    @State private var assignedToUID = ""
    @State private var isChecklist = false
    @State private var items: [Chore.ChecklistItem] = []

    /// Items with real content — a blank row left over from tapping "Add
    /// item" without filling it in doesn't count as part of the checklist.
    private var nonBlankItems: [Chore.ChecklistItem] {
        items.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var childMembers: [(uid: String, name: String)] {
        guard let members = household?.members else { return [] }
        return members
            .filter { $0.value.role == .child }
            .map { (uid: $0.key, name: $0.value.name) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore") {
                    TextField("Title", text: $title)
                    Stepper("Points: \(points)", value: $points, in: 1...100)
                }

                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Chore.iconChoices, id: \.self) { name in
                                Image(systemName: name)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(icon == name ? Color.accentColor.opacity(0.2) : .clear)
                                    .clipShape(Circle())
                                    .onTapGesture { icon = name }
                            }
                        }
                    }
                }

                Section("Repeats") {
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(Chore.Recurrence.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if recurrence == .weekly {
                        HStack {
                            ForEach(0..<7, id: \.self) { day in
                                let selected = weeklyDays.contains(day)
                                Text(Self.weekdaySymbols[day])
                                    .font(.caption.bold())
                                    .frame(width: 36, height: 36)
                                    .background(selected ? Color.accentColor : Color.gray.opacity(0.2))
                                    .foregroundStyle(selected ? .white : .primary)
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        if selected { weeklyDays.remove(day) } else { weeklyDays.insert(day) }
                                    }
                            }
                        }
                    }
                }

                Section("Checklist") {
                    Toggle("Use a checklist", isOn: $isChecklist)
                    if isChecklist {
                        // Every row shares the "Item" placeholder, so a UI
                        // test can't tell them apart by label alone — indexed
                        // by position, since a freshly-added item's UUID
                        // isn't known ahead of time.
                        // An explicit trailing delete button, not swipe-to-
                        // delete or a forced system edit mode: swiping a row
                        // whose content is an editable TextField turned out
                        // to be unreliable (the gesture didn't register),
                        // and it's an awkward gesture to discover on a text
                        // field either way. Reordering is via remove-and-
                        // re-add rather than a drag handle, for the same
                        // reliability reason.
                        ForEach(items.indices, id: \.self) { index in
                            HStack {
                                TextField("Item", text: $items[index].title)
                                    .accessibilityIdentifier("checklistItemTitleField-\(index)")
                                Button {
                                    items.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("checklistItemDeleteButton-\(index)")
                            }
                        }

                        Button {
                            items.append(Chore.ChecklistItem(id: UUID().uuidString, title: ""))
                        } label: {
                            Label("Add item", systemImage: "plus.circle")
                        }

                        Text("Points are awarded once, when every item is checked — not per item.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Assigned to") {
                    if childMembers.isEmpty {
                        Text("Invite a child from Settings first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Assigned to", selection: $assignedToUID) {
                            ForEach(childMembers, id: \.uid) { child in
                                Text(child.name).tag(child.uid)
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingChore == nil ? "New Chore" : "Edit Chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            title.isEmpty || assignedToUID.isEmpty
                                || (recurrence == .weekly && weeklyDays.isEmpty)
                                || (isChecklist && nonBlankItems.isEmpty)
                        )
                }
            }
            .onAppear(perform: populateIfEditing)
        }
    }

    private func populateIfEditing() {
        guard let chore = editingChore else {
            if assignedToUID.isEmpty {
                assignedToUID = childMembers.first?.uid ?? ""
            }
            return
        }
        title = chore.title
        points = chore.points
        icon = chore.icon
        recurrence = chore.recurrence
        weeklyDays = Set(chore.weeklyDays)
        assignedToUID = chore.assignedToUID
        isChecklist = chore.isChecklist
        items = chore.items
    }

    private func save() {
        var chore = editingChore ?? Chore(
            title: "",
            icon: icon,
            points: points,
            recurrence: recurrence,
            weeklyDays: [],
            assignedToUID: assignedToUID,
            isActive: true,
            items: []
        )
        chore.title = title
        chore.icon = icon
        chore.points = points
        chore.recurrence = recurrence
        chore.weeklyDays = Array(weeklyDays).sorted()
        chore.assignedToUID = assignedToUID
        // Editing the list never affects past days — see design.md. Toggling
        // "Use a checklist" off clears items entirely; toggling it on with
        // nothing typed yet is blocked by the Save button's disabled state.
        chore.items = isChecklist ? nonBlankItems : []

        if editingChore == nil {
            choreStore.addChore(chore)
        } else {
            choreStore.updateChore(chore)
        }
        dismiss()
    }
}

#Preview {
    AddEditChoreView(choreStore: ChoreStore(), household: nil)
}
