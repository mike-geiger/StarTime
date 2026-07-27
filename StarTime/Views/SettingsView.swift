import FirebaseAuth
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore

    @State private var generatedCode: String?
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let household = householdStore.household {
                    Section("Household") {
                        Text(household.name)
                        ForEach(sortedMembers(household), id: \.uid) { member in
                            HStack {
                                Text(member.uid == auth.user?.uid ? "\(member.name) (You)" : member.name)
                                Spacer()
                                Text(member.role.rawValue.capitalized)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if householdStore.profile?.role == .parent {
                        Section {
                            Button {
                                generateCode(role: .parent)
                            } label: {
                                Label("Invite a parent", systemImage: "person.fill.badge.plus")
                            }
                            Button {
                                generateCode(role: .child)
                            } label: {
                                Label("Invite a child", systemImage: "figure.child")
                            }

                            if let generatedCode {
                                HStack {
                                    Text(generatedCode)
                                        .font(.title2.monospaced().bold())
                                        .accessibilityIdentifier("generatedInviteCode")
                                    Spacer()
                                    ShareLink(item: "Join our Star Time household \"\(household.name)\" — use invite code \(generatedCode) in the Star Time app.")
                                }
                            }
                        } header: {
                            Text("Invite someone")
                        } footer: {
                            Text("Generate a code and share it with a family member so they can join this household.")
                        }
                    }
                } else {
                    Section {
                        ProgressView()
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) { try? auth.signOut() }
                }

                Section {
                    Button("Delete Account", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("deleteAccountRowButton")
                    .disabled(isDeletingAccount)

                    if let deleteErrorMessage {
                        Text(deleteErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Permanently deletes your account. If you're the last member of this household, its chores, rewards, and history are deleted too.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete your account? This can't be undone.",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func sortedMembers(_ household: Household) -> [(uid: String, name: String, role: Household.Role)] {
        household.members
            .map { (uid: $0.key, name: $0.value.name, role: $0.value.role) }
            .sorted { $0.name < $1.name }
    }

    private func generateCode(role: Household.Role) {
        guard let uid = auth.user?.uid else { return }
        Task {
            generatedCode = await householdStore.generateInviteCode(role: role, uid: uid)
        }
    }

    private func deleteAccount() {
        guard let uid = auth.user?.uid else { return }
        isDeletingAccount = true
        deleteErrorMessage = nil
        Task {
            let dataCleanedUp = await householdStore.deleteAccountData(uid: uid)
            guard dataCleanedUp else {
                deleteErrorMessage = householdStore.errorMessage ?? "Something went wrong deleting your data. Please try again."
                isDeletingAccount = false
                return
            }
            do {
                try await auth.deleteAccount()
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
