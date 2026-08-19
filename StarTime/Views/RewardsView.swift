import SwiftUI

struct RewardsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore
    @EnvironmentObject private var rewardStore: RewardStore

    @State private var showingAddReward = false
    @State private var editingReward: Reward?
    /// Cancelling returns points, so it asks first. Holding the redemption
    /// itself (rather than a bool) keeps the confirmation bound to the row
    /// that was swiped even if the list reorders underneath it.
    @State private var redemptionPendingCancellation: Redemption?
    /// Same shape as cancellation, for the same reason: un-fulfilling had no
    /// confirmation at all before this, and now both reversals share a
    /// moment to explain why.
    @State private var redemptionPendingUnfulfillment: Redemption?
    /// Backs the note field in whichever of the two alerts above is showing.
    /// Only one can be presented at a time, so sharing this is safe.
    @State private var reversalNoteDraft = ""

    private var isParent: Bool { householdStore.profile?.role == .parent }

    var body: some View {
        NavigationStack {
            List {
                if isParent {
                    pendingQueueSection

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

                    resolvedHistorySection
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
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(redemption.rewardName)
                                        // Without this a request a parent
                                        // hasn't acted on yet is
                                        // indistinguishable from a reward
                                        // already in hand.
                                        statusPill(redemption.status)
                                        reversalNoteText(redemption)
                                    }
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
        // `.confirmationDialog` can't host a `TextField`, so the optional
        // note pushed this to `.alert`, which can embed one in `actions`.
        .alert(
            "Cancel this request?",
            isPresented: Binding(
                get: { redemptionPendingCancellation != nil },
                set: { if !$0 { redemptionPendingCancellation = nil; reversalNoteDraft = "" } }
            ),
            presenting: redemptionPendingCancellation
        ) { redemption in
            TextField("Note (optional)", text: $reversalNoteDraft)
            Button("Cancel and return \(redemption.pointsSpent) points", role: .destructive) {
                rewardStore.cancel(redemption, note: resolvedNoteDraft)
                redemptionPendingCancellation = nil
                reversalNoteDraft = ""
            }
            Button("Keep it", role: .cancel) {
                redemptionPendingCancellation = nil
                reversalNoteDraft = ""
            }
        } message: { redemption in
            Text("\(redemption.redeemedByName) will get their \(redemption.pointsSpent) points back.")
        }
        .alert(
            "Un-fulfill this reward?",
            isPresented: Binding(
                get: { redemptionPendingUnfulfillment != nil },
                set: { if !$0 { redemptionPendingUnfulfillment = nil; reversalNoteDraft = "" } }
            ),
            presenting: redemptionPendingUnfulfillment
        ) { redemption in
            TextField("Note (optional)", text: $reversalNoteDraft)
            // Named for its consequence, like the cancel alert's confirm
            // button -- and distinct from the swipe action's plain
            // "Un-fulfill" label, which triggers this alert rather than
            // performing the transition itself.
            Button("Un-fulfill and return to queue", role: .destructive) {
                rewardStore.unfulfill(redemption, note: resolvedNoteDraft)
                redemptionPendingUnfulfillment = nil
                reversalNoteDraft = ""
            }
            Button("Keep as fulfilled", role: .cancel) {
                redemptionPendingUnfulfillment = nil
                reversalNoteDraft = ""
            }
        } message: { redemption in
            Text("\(redemption.redeemedByName) will need to wait for it again.")
        }
    }

    /// `nil` rather than an empty string when the field was left blank, so a
    /// blank submission clears any previous note instead of storing "".
    private var resolvedNoteDraft: String? {
        let trimmed = reversalNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Parent sections

    /// The whole point of the queue: requests that are waiting on this parent,
    /// ahead of everything else on the screen. Absent entirely when empty --
    /// an empty work queue is not worth a row.
    @ViewBuilder
    private var pendingQueueSection: some View {
        let pending = rewardStore.pendingRedemptions
        if !pending.isEmpty {
            Section {
                ForEach(pending) { redemption in
                    pendingRow(redemption)
                }
            } header: {
                Label("Waiting on you", systemImage: "clock.badge.exclamationmark")
            }
        }
    }

    @ViewBuilder
    private func pendingRow(_ redemption: Redemption) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(redemption.redeemedByName) wants \(redemption.rewardName)")
                HStack(spacing: 6) {
                    Text("\(redemption.pointsSpent) pts")
                    if let redeemedAt = redemption.redeemedAt {
                        Text("·")
                        Text(redeemedAt, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                // Present when this is back in the queue because a parent
                // un-fulfilled it with a note, rather than a fresh request.
                reversalNoteText(redemption)
            }

            Spacer()

            Button("Fulfilled") { rewardStore.fulfill(redemption) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fulfillRedemptionButton-\(redemption.id ?? "")")
        }
        .accessibilityIdentifier("pendingRedemptionRow-\(redemption.id ?? "")")
        .swipeActions {
            Button("Cancel", role: .destructive) {
                redemptionPendingCancellation = redemption
            }
            .accessibilityIdentifier("cancelRedemptionButton-\(redemption.id ?? "")")
        }
    }

    /// Fulfilled and cancelled requests. Exists so a parent who tapped
    /// "Fulfilled" by mistake has something to swipe on -- reverting is the
    /// only way back, since cancelling a fulfilled redemption is refused.
    @ViewBuilder
    private var resolvedHistorySection: some View {
        let resolved = rewardStore.redemptions
            .filter { $0.status != .pending }
            .sorted { ($0.redeemedAt ?? .distantPast) > ($1.redeemedAt ?? .distantPast) }

        if !resolved.isEmpty {
            Section("History") {
                ForEach(resolved) { redemption in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(redemption.redeemedByName) — \(redemption.rewardName)")
                            statusPill(redemption.status)
                            reversalNoteText(redemption)
                        }
                        Spacer()
                        Text("-\(redemption.pointsSpent)")
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if redemption.status == .fulfilled {
                            Button("Un-fulfill") { redemptionPendingUnfulfillment = redemption }
                                .tint(.orange)
                                .accessibilityIdentifier("unfulfillRedemptionButton-\(redemption.id ?? "")")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private func statusPill(_ status: RedemptionStatus) -> some View {
        switch status {
        case .pending:
            Label("Waiting on a parent", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.orange)
        case .fulfilled:
            Label("Received", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .cancelled:
            Label("Cancelled — points returned", systemImage: "arrow.uturn.backward")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Only ever non-nil after a cancel or un-fulfil that included one, and
    /// cleared server-side the moment the redemption is fulfilled again, so
    /// this never shows a note that's since been superseded.
    @ViewBuilder
    private func reversalNoteText(_ redemption: Redemption) -> some View {
        if let note = redemption.reversalNote, !note.isEmpty {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
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
