import SwiftUI

struct RewardsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var rewardStore: RewardStore

    @State private var showingAddReward = false
    @State private var editingReward: Reward?

    private var isParent: Bool { householdStore.profile?.role == .parent }

    var body: some View {
        NavigationStack {
            List {
                if isParent {
                    ForEach(childMembers, id: \.uid) { child in
                        Section {
                            if rewardStore.rewards.isEmpty {
                                Text("No rewards yet — add one with the + button.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(rewardStore.rewards) { reward in
                                    rewardRow(reward, uid: child.uid, name: child.name)
                                }
                            }
                        } header: {
                            HStack {
                                Text(child.name)
                                Spacer()
                                Label("\(rewardStore.balance(for: child.uid))", systemImage: "star.fill")
                            }
                        }
                    }
                    if childMembers.isEmpty {
                        Text("Invite a child from Settings to start earning points.")
                            .foregroundStyle(.secondary)
                    }
                } else if let myUID = auth.user?.uid {
                    Section {
                        HStack {
                            Text("Your points")
                            Spacer()
                            Label("\(rewardStore.balance(for: myUID))", systemImage: "star.fill")
                                .font(.title3.bold())
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("Rewards") {
                        if rewardStore.rewards.isEmpty {
                            Text("No rewards yet — ask a parent to add some!")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(rewardStore.rewards) { reward in
                                rewardRow(reward, uid: myUID, name: householdStore.profile?.name ?? "Me")
                            }
                        }
                    }

                    let myRedemptions = rewardStore.redemptions(for: myUID)
                    if !myRedemptions.isEmpty {
                        Section("Redeemed") {
                            ForEach(myRedemptions) { redemption in
                                HStack {
                                    Text(redemption.rewardName)
                                    Spacer()
                                    Text("-\(redemption.pointsSpent)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rewards")
            .toolbar {
                if isParent {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingAddReward = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showingAddReward) {
                AddEditRewardView(rewardStore: rewardStore)
            }
            .sheet(item: $editingReward) { reward in
                AddEditRewardView(rewardStore: rewardStore, editingReward: reward)
            }
        }
        // Redeeming can now fail server-side (not enough points, including
        // the racing-redemption case the old local check couldn't catch),
        // so that has to be visible rather than silently doing nothing.
        .alert(
            // Neutral, because `errorMessage` covers reward edits/deletes
            // too -- the message text carries the specifics.
            "Something went wrong",
            isPresented: Binding(
                get: { rewardStore.errorMessage != nil },
                set: { if !$0 { rewardStore.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { rewardStore.errorMessage = nil }
        } message: {
            Text(rewardStore.errorMessage ?? "")
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
    private func rewardRow(_ reward: Reward, uid: String, name: String) -> some View {
        let canAfford = rewardStore.balance(for: uid) >= reward.pointCost

        HStack {
            Image(systemName: reward.icon)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(reward.name)
                Text("\(reward.pointCost) pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Redeem") {
                rewardStore.redeem(reward, forUID: uid, name: name)
            }
            .buttonStyle(.bordered)
            .disabled(!canAfford)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isParent { editingReward = reward }
        }
        .swipeActions {
            if isParent {
                Button("Delete", role: .destructive) { rewardStore.deleteReward(reward) }
            }
        }
    }
}

#Preview {
    RewardsView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
