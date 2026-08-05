import SwiftUI

/// Auth gate: routes to sign-in, household setup, or the main app depending
/// on where the current user is in the onboarding flow.
struct ContentView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var householdStore = HouseholdStore()

    var body: some View {
        Group {
            if auth.isRestoringSession {
                ProgressView()
            } else if let user = auth.user {
                if householdStore.isLoading {
                    ProgressView()
                } else if householdStore.household != nil {
                    MainTabView()
                } else {
                    HouseholdSetupView()
                }
            } else {
                AuthView()
            }
        }
        .environmentObject(householdStore)
        .task {
            await auth.restoreSession()
        }
        .task(id: auth.user?.uid) {
            if auth.user != nil {
                await householdStore.loadForCurrentUser()
            } else {
                householdStore.reset()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
