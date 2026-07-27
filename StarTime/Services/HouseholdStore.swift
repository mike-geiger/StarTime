import Combine
import Foundation

@MainActor
final class HouseholdStore: ObservableObject {
    @Published private(set) var household: Household?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service = HouseholdService()

    func loadForCurrentUser(uid: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let profile = try await service.fetchProfile(uid: uid) else {
                self.profile = nil
                self.household = nil
                return
            }
            self.profile = profile
            if let householdId = profile.householdId {
                self.household = try await service.fetchHousehold(id: householdId)
            } else {
                self.household = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createHousehold(name: String, uid: String, displayName: String) async {
        do {
            household = try await service.createHousehold(name: name, uid: uid, displayName: displayName)
            profile = UserProfile(name: displayName, householdId: household?.id, role: .parent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func joinHousehold(code: String, uid: String, displayName: String) async {
        do {
            household = try await service.joinHousehold(code: code.uppercased(), uid: uid, displayName: displayName)
            profile = try await service.fetchProfile(uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateInviteCode(role: Household.Role, uid: String) async -> String? {
        guard let householdId = household?.id else { return nil }
        do {
            return try await service.generateInviteCode(householdId: householdId, role: role, createdByUID: uid)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Cleans up this user's Firestore data (household membership, cascading
    /// to a full household delete if they were the last member, plus their
    /// own profile doc). Returns whether it succeeded — the caller must only
    /// delete the Auth account itself on success, since that step can't be
    /// undone and shouldn't proceed while this data is potentially orphaned.
    func deleteAccountData(uid: String) async -> Bool {
        do {
            if let householdId = household?.id {
                try await service.leaveHousehold(householdId: householdId, uid: uid)
            }
            try await service.deleteUserProfile(uid: uid)
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
