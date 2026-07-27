import Combine
import FirebaseAuth

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var user: User?

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signUp(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        try await Auth.auth().currentUser?.delete()
    }
}
