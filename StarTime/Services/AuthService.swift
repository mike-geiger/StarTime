import AWSCognitoIdentityProvider
import Combine
import Foundation

/// Lightweight replacement for Firebase's `User` -- `uid` is always the
/// `custom:legacy_uid` claim (see backend/cdk/lib/auth-stack.ts), never
/// Cognito's own `sub`, so every other Service/Store that keys data off a
/// uid string keeps working unchanged.
struct AuthUser: Equatable {
    let uid: String
    let email: String?
}

enum AuthServiceError: LocalizedError {
    case missingSession
    case malformedToken

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "You're not signed in."
        case .malformedToken:
            return "Couldn't read your session. Please sign in again."
        }
    }
}

@MainActor
final class AuthService: ObservableObject, AuthTokenProviding {
    @Published private(set) var user: AuthUser?
    /// True until the initial keychain-backed session restore (see
    /// `restoreSession()`) finishes -- lets ContentView show a spinner
    /// instead of flashing the sign-in screen on cold launch.
    @Published private(set) var isRestoringSession = true

    private let client: CognitoIdentityProviderClient
    private let clientId: String
    private let tokenStore: KeychainTokenStore

    init(tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        // A missing/invalid region is a build-time misconfiguration (see
        // StarTime/Config/StarTime.xcconfig), not a runtime condition to
        // recover from.
        self.client = try! CognitoIdentityProviderClient(region: BackendConfig.awsRegion)
        self.clientId = BackendConfig.userPoolClientId
        self.tokenStore = tokenStore
        // Registered here rather than from the App's body so it's guaranteed
        // to happen before any view can trigger a request -- AuthService is
        // constructed at app launch, before the first render.
        APIClient.shared.tokenProvider = self
    }

    // MARK: - AuthTokenProviding

    /// The bearer token APIClient attaches to every request.
    var idToken: String? { tokenStore.idToken }

    /// Called by APIClient after a 401, to recover from an expired ID token
    /// without bouncing the user back to the sign-in screen.
    func refreshTokens() async throws {
        guard let refreshToken = tokenStore.refreshToken else {
            throw AuthServiceError.missingSession
        }
        try await refresh(refreshToken: refreshToken)
    }

    // MARK: - Session

    func restoreSession() async {
        defer { isRestoringSession = false }
        guard let refreshToken = tokenStore.refreshToken else { return }
        do {
            try await refresh(refreshToken: refreshToken)
        } catch {
            tokenStore.clear()
        }
    }

    func signUp(email: String, password: String) async throws {
        _ = try await client.signUp(input: SignUpInput(clientId: clientId, password: password, username: email))
        // SignUp doesn't return tokens (unlike Firebase's createUser) -- the
        // PreSignUp trigger auto-confirms, so this immediate sign-in matches
        // today's instant-signed-in-after-signup UX.
        try await signIn(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        let output = try await client.initiateAuth(input: InitiateAuthInput(
            authFlow: .userPasswordAuth,
            authParameters: ["USERNAME": email, "PASSWORD": password],
            clientId: clientId
        ))
        try apply(output.authenticationResult, fallbackRefreshToken: nil)
    }

    func signOut() throws {
        tokenStore.clear()
        user = nil
    }

    func deleteAccount() async throws {
        guard let accessToken = tokenStore.accessToken else { throw AuthServiceError.missingSession }
        _ = try await client.deleteUser(input: DeleteUserInput(accessToken: accessToken))
        try signOut()
    }

    private func refresh(refreshToken: String) async throws {
        let output = try await client.initiateAuth(input: InitiateAuthInput(
            authFlow: .refreshTokenAuth,
            authParameters: ["REFRESH_TOKEN": refreshToken],
            clientId: clientId
        ))
        // The refresh flow doesn't always return a new refresh token; keep
        // reusing the existing one when it doesn't.
        try apply(output.authenticationResult, fallbackRefreshToken: refreshToken)
    }

    private func apply(_ result: CognitoIdentityProviderClientTypes.AuthenticationResultType?, fallbackRefreshToken: String?) throws {
        guard let idToken = result?.idToken,
              let accessToken = result?.accessToken,
              let refreshToken = result?.refreshToken ?? fallbackRefreshToken else {
            throw AuthServiceError.missingSession
        }

        let claims = try JWT.claims(from: idToken)
        guard let uid = claims["custom:legacy_uid"] as? String else {
            throw AuthServiceError.malformedToken
        }

        tokenStore.save(idToken: idToken, accessToken: accessToken, refreshToken: refreshToken)
        user = AuthUser(uid: uid, email: claims["email"] as? String)
    }
}
