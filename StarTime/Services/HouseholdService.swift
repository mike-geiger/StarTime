import Foundation

enum HouseholdServiceError: LocalizedError {
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "That invite code isn't valid. Double-check it and try again."
        }
    }
}

struct HouseholdService {
    private var api: APIClient { APIClient.shared }

    /// The combined profile + household read. Both are optional: a
    /// brand-new sign-up has neither yet, which is expected rather than
    /// an error (same contract the old Optional-decoding `fetchProfile` had).
    struct MeResponse: Decodable {
        var profile: UserProfile?
        var household: Household?
    }

    @MainActor
    func fetchMe() async throws -> MeResponse {
        try await api.send("GET", "households/me", as: MeResponse.self)
    }

    @MainActor
    func createHousehold(name: String, displayName: String) async throws -> Household {
        struct Body: Encodable {
            let name: String
            let displayName: String
        }
        struct Response: Decodable {
            let household: Household
        }
        let response = try await api.send(
            "POST", "households",
            body: Body(name: name, displayName: displayName),
            as: Response.self
        )
        return response.household
    }

    @MainActor
    func joinHousehold(code: String, displayName: String) async throws -> Household {
        struct Body: Encodable {
            let code: String
            let displayName: String
        }
        struct Response: Decodable {
            let household: Household
        }
        do {
            let response = try await api.send(
                "POST", "households/join",
                body: Body(code: code, displayName: displayName),
                as: Response.self
            )
            return response.household
        } catch let error as APIError where error.statusCode == 404 {
            // The handler returns 404 both for an unknown code and for one
            // pointing at an already-deleted household -- either way it's
            // the same thing from the user's perspective.
            throw HouseholdServiceError.invalidCode
        }
    }

    @MainActor
    func generateInviteCode(role: Household.Role) async throws -> String {
        struct Body: Encodable {
            let role: String
        }
        struct Response: Decodable {
            let code: String
        }
        let response = try await api.send(
            "POST", "households/invite-codes",
            body: Body(role: role.rawValue),
            as: Response.self
        )
        return response.code
    }

    /// Removes the caller from their household — cascading to a full
    /// household delete if they were the last member — and deletes their
    /// profile. Combines what used to be `leaveHousehold` +
    /// `deleteUserProfile`, which were only ever called together.
    @MainActor
    func deleteAccountData() async throws {
        try await api.send("DELETE", "account")
    }
}
