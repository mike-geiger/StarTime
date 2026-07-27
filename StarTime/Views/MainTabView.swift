import SwiftUI

struct MainTabView: View {
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
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
        .environmentObject(HouseholdStore())
}
