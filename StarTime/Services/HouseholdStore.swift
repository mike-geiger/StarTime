import Combine
import Foundation

@MainActor
final class HouseholdStore: ObservableObject {
    @Published private(set) var household: Household?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service = HouseholdService()

    // None of these take a uid any more: every handler derives the caller's
    // identity from the Cognito token claims the API Gateway authorizer
    // already validated, so a client-supplied uid would be both redundant
    // and misleading about who actually controls identity.

    func loadForCurrentUser() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await service.fetchMe()
            profile = me.profile
            household = me.household
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createHousehold(name: String, displayName: String) async {
        do {
            household = try await service.createHousehold(name: name, displayName: displayName)
            profile = UserProfile(name: displayName, householdId: household?.id, role: .parent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func joinHousehold(code: String, displayName: String) async {
        do {
            household = try await service.joinHousehold(code: code.uppercased(), displayName: displayName)
            profile = try await service.fetchMe().profile
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateInviteCode(role: Household.Role) async -> String? {
        do {
            return try await service.generateInviteCode(role: role)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Cleans up this user's household data (membership, cascading to a full
    /// household delete if they were the last member, plus their own
    /// profile). Returns whether it succeeded — the caller must only delete
    /// the Auth account itself on success, since that step can't be undone
    /// and shouldn't proceed while this data is potentially orphaned.
    func deleteAccountData() async -> Bool {
        do {
            try await service.deleteAccountData()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset() {
        household = nil
        profile = nil
    }
}
