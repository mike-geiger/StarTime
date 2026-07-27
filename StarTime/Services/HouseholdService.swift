import FirebaseFirestore

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
    private let db = Firestore.firestore()

    private static let codeCharacters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no 0/O/1/I

    func fetchProfile(uid: String) async throws -> UserProfile? {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        // Decoding as an explicit Optional type tells the Codable bridge to
        // return nil for a missing document instead of throwing — correct
        // here since "no profile yet" (brand-new sign-up) is expected, not
        // an error. (Same pattern already used for the invite-code lookup
        // below, just missed here originally.)
        return try snapshot.data(as: UserProfile?.self)
    }

    func fetchHousehold(id: String) async throws -> Household {
        try await db.collection("households").document(id).getDocument(as: Household.self)
    }

    func createHousehold(name: String, uid: String, displayName: String) async throws -> Household {
        let member = Household.Member(name: displayName, role: .parent)
        var household = Household(name: name, members: [uid: member])
        let ref = db.collection("households").document()
        try ref.setData(from: household)
        household.id = ref.documentID

        let profile = UserProfile(name: displayName, householdId: ref.documentID, role: .parent)
        try db.collection("users").document(uid).setData(from: profile)

        return household
    }

    func joinHousehold(code: String, uid: String, displayName: String) async throws -> Household {
        let codeDoc = try await db.collection("inviteCodes").document(code).getDocument()
        guard let invite = try codeDoc.data(as: InviteCode?.self) else {
            throw HouseholdServiceError.invalidCode
        }

        let householdRef = db.collection("households").document(invite.householdId)
        try await householdRef.updateData([
            "members.\(uid)": ["name": displayName, "role": invite.role.rawValue],
            "lastJoinCode": code
        ])

        let profile = UserProfile(name: displayName, householdId: invite.householdId, role: invite.role)
        try db.collection("users").document(uid).setData(from: profile)

        return try await fetchHousehold(id: invite.householdId)
    }

    func generateInviteCode(householdId: String, role: Household.Role, createdByUID: String) async throws -> String {
        let code = String((0..<6).map { _ in Self.codeCharacters.randomElement()! })
        let invite = InviteCode(householdId: householdId, role: role, createdByUID: createdByUID)
        try db.collection("inviteCodes").document(code).setData(from: invite)
        return code
    }

    /// Removes `uid` from the household. If they were the last member, the
    /// whole household — chores, completions, rewards, redemptions, and any
    /// invite codes pointing at it — is cascade-deleted rather than left
    /// behind as an orphan. The invite-code lookup relies on a `list` query
    /// scoped to this exact householdId, which the security rules only allow
    /// when the requester is still a member of that specific household —
    /// it can't be used to enumerate any other household's codes.
    func leaveHousehold(householdId: String, uid: String) async throws {
        let householdRef = db.collection("households").document(householdId)
        let household = try await householdRef.getDocument(as: Household.self)
        let remainingMembers = household.members.filter { $0.key != uid }

        guard remainingMembers.isEmpty else {
            try await householdRef.updateData(["members.\(uid)": FieldValue.delete()])
            return
        }

        try await deleteAllDocuments(in: householdRef.collection("completions"))
        try await deleteAllDocuments(in: householdRef.collection("redemptions"))
        try await deleteAllDocuments(in: householdRef.collection("chores"))
        try await deleteAllDocuments(in: householdRef.collection("rewards"))

        let codes = try await db.collection("inviteCodes")
            .whereField("householdId", isEqualTo: householdId)
            .getDocuments()
        for doc in codes.documents {
            try await doc.reference.delete()
        }

        try await householdRef.delete()
    }

    func deleteUserProfile(uid: String) async throws {
        try await db.collection("users").document(uid).delete()
    }

    private func deleteAllDocuments(in collection: CollectionReference) async throws {
        let snapshot = try await collection.getDocuments()
        guard !snapshot.documents.isEmpty else { return }
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }
}
