import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var householdStore: HouseholdStore
    @Environment(\.scenePhase) private var scenePhase

    // One store per feature area, shared across the tabs that read it.
    // These used to be per-view @StateObjects, which Firestore's snapshot
    // listeners quietly compensated for by pushing every write to all of
    // them. Without listeners a write made through one instance is invisible
    // to the others, so sharing is now a correctness requirement, not just
    // an efficiency one.
    @StateObject private var choreStore = ChoreStore()
    @StateObject private var rewardStore = RewardStore()
    @StateObject private var realtime = RealtimeConnectionManager()

    var body: some View {
        TabView {
            ChoresView()
                .tabItem { Label("Chores", systemImage: "checklist") }

            RewardsView()
                .tabItem { Label("Rewards", systemImage: "star.fill") }

            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .environmentObject(choreStore)
        .environmentObject(rewardStore)
        .task(id: householdStore.household?.id) {
            guard let householdId = householdStore.household?.id else { return }
            // Subscribe before starting: an invalidation that lands during
            // the initial fetch should still trigger a refetch.
            choreStore.observe(realtime)
            rewardStore.observe(realtime)
            choreStore.start(householdId: householdId)
            rewardStore.start(householdId: householdId)
            if let idToken = auth.idToken {
                realtime.start(idToken: idToken)
            }
        }
        // iOS suspends a backgrounded app and tears down its WebSocket, but
        // the suspended app never observes that failure -- so it can't
        // self-heal via the reconnect path. Coming back to the foreground has
        // to both re-establish the socket and refetch, since any change made
        // while we were away was pushed to a connection that no longer exists.
        .onChange(of: scenePhase) { _, phase in
            guard householdStore.household?.id != nil else { return }
            switch phase {
            case .active:
                choreStore.refresh()
                rewardStore.refresh()
                if let idToken = auth.idToken {
                    realtime.start(idToken: idToken)
                }
            case .background:
                realtime.stop()
            default:
                break
            }
        }
        .onDisappear { realtime.stop() }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
