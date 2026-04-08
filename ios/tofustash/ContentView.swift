import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Habits", systemImage: "checkmark.circle") {
                HabitsView()
            }
            Tab("Rewards", systemImage: "gift") {
                RewardsView()
            }
            Tab("Trades", systemImage: "arrow.left.arrow.right") {
                TradesView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView()
        .environment(AuthManager(
            apiClient: LiveAuthAPIClient(baseURL: URL(string: "http://localhost:8501")!),
            tokenStorage: KeychainTokenStorage()
        ))
}
