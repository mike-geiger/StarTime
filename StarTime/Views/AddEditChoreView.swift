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
                        .disabled(title.isEmpty || assignedToUID.isEmpty || (recurrence == .weekly && weeklyDays.isEmpty))
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
    }

    private func save() {
        var chore = editingChore ?? Chore(
            title: "",
            icon: icon,
            points: points,
            recurrence: recurrence,
            weeklyDays: [],
            assignedToUID: assignedToUID,
            isActive: true
        )
        chore.title = title
        chore.icon = icon
        chore.points = points
        chore.recurrence = recurrence
        chore.weeklyDays = Array(weeklyDays).sorted()
        chore.assignedToUID = assignedToUID

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
