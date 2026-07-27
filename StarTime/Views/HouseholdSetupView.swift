import FirebaseAuth
import SwiftUI

struct HouseholdSetupView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore

    private enum Mode {
        case choose, create, join
    }

    @State private var mode: Mode = .choose
    @State private var displayName = ""
    @State private var householdName = ""
    @State private var inviteCode = ""
    @State private var isSubmitting = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .choose:
                    chooseView
                case .create:
                    createView
                case .join:
                    joinView
                }
            }
            .padding()
            .navigationTitle("Welcome")
        }
    }

    private var chooseView: some View {
        VStack(spacing: 16) {
            Text("Let's get your family set up.")
                .font(.title3)
            Button("Create a household") { mode = .create }
                .buttonStyle(.borderedProminent)
            Button("Join with an invite code") { mode = .join }
                .buttonStyle(.bordered)
            Divider().padding(.vertical)
            Button("Sign Out", role: .destructive) { try? auth.signOut() }

            Button("Delete Account", role: .destructive) {
                showingDeleteConfirmation = true
            }
            .accessibilityIdentifier("deleteAccountRowButton")
            .disabled(isDeletingAccount)
            .font(.footnote)

            if let deleteErrorMessage {
                Text(deleteErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(
            "Delete your account? This can't be undone.",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
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

    private var createView: some View {
        VStack(spacing: 16) {
            TextField("Your name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            TextField("Household name (e.g. \"The Geigers\")", text: $householdName)
                .textFieldStyle(.roundedBorder)

            if let error = householdStore.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button("Create") {
                guard let uid = auth.user?.uid else { return }
                isSubmitting = true
                Task {
                    await householdStore.createHousehold(name: householdName, uid: uid, displayName: displayName)
                    isSubmitting = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(displayName.isEmpty || householdName.isEmpty || isSubmitting)

            Button("Back") { mode = .choose }
        }
    }

    private var joinView: some View {
        VStack(spacing: 16) {
            TextField("Your name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            TextField("Invite code", text: $inviteCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            if let error = householdStore.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button("Join") {
                guard let uid = auth.user?.uid else { return }
                isSubmitting = true
                Task {
                    await householdStore.joinHousehold(code: inviteCode, uid: uid, displayName: displayName)
                    isSubmitting = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(displayName.isEmpty || inviteCode.isEmpty || isSubmitting)

            Button("Back") { mode = .choose }
        }
    }
}

#Preview {
    HouseholdSetupView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
