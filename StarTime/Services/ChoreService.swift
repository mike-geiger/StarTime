import FirebaseFirestore

struct ChoreService {
    private let db = Firestore.firestore()

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    func choresListener(householdId: String, onChange: @escaping ([Chore]) -> Void) -> ListenerRegistration {
        db.collection("households").document(householdId).collection("chores")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { snapshot, _ in
                let chores = snapshot?.documents.compactMap { try? $0.data(as: Chore.self) } ?? []
                onChange(chores)
            }
    }

    func completionsListener(householdId: String, since: Date, onChange: @escaping ([ChoreCompletion]) -> Void) -> ListenerRegistration {
        db.collection("households").document(householdId).collection("completions")
            .whereField("completedAt", isGreaterThan: Timestamp(date: since))
            .addSnapshotListener { snapshot, _ in
                let completions = snapshot?.documents.compactMap { try? $0.data(as: ChoreCompletion.self) } ?? []
                onChange(completions)
            }
    }

    func addChore(householdId: String, chore: Chore) throws {
        let ref = db.collection("households").document(householdId).collection("chores").document()
        try ref.setData(from: chore)
    }

    func updateChore(householdId: String, chore: Chore) throws {
        guard let choreId = chore.id else { return }
        try db.collection("households").document(householdId).collection("chores").document(choreId).setData(from: chore)
    }

    func deleteChore(householdId: String, choreId: String) async throws {
        try await db.collection("households").document(householdId).collection("chores").document(choreId).delete()
    }

    func recordCompletion(householdId: String, completion: ChoreCompletion) throws {
        let ref = db.collection("households").document(householdId).collection("completions").document()
        try ref.setData(from: completion)
    }
}
