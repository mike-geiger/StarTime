import SwiftUI

struct AddEditRewardView: View {
    @Environment(\.dismiss) private var dismiss

    var rewardStore: RewardStore
    var editingReward: Reward?

    @State private var name = ""
    @State private var pointCost = 20
    @State private var icon = Reward.iconChoices[0]

    var body: some View {
        NavigationStack {
            Form {
                Section("Reward") {
                    TextField("Name", text: $name)
                    Stepper("Cost: \(pointCost) pts", value: $pointCost, in: 1...1000, step: 5)
                }

                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Reward.iconChoices, id: \.self) { choice in
                                Image(systemName: choice)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(icon == choice ? Color.accentColor.opacity(0.2) : .clear)
                                    .clipShape(Circle())
                                    .onTapGesture { icon = choice }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingReward == nil ? "New Reward" : "Edit Reward")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear(perform: populateIfEditing)
        }
    }

    private func populateIfEditing() {
        guard let reward = editingReward else { return }
        name = reward.name
        pointCost = reward.pointCost
        icon = reward.icon
    }

    private func save() {
        var reward = editingReward ?? Reward(name: "", icon: icon, pointCost: pointCost, isActive: true)
        reward.name = name
        reward.pointCost = pointCost
        reward.icon = icon

        if editingReward == nil {
            rewardStore.addReward(reward)
        } else {
            rewardStore.updateReward(reward)
        }
        dismiss()
    }
}

#Preview {
    AddEditRewardView(rewardStore: RewardStore())
}
