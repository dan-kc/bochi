import SwiftUI

@main
struct tofustashApp: App {
    @State private var authManager = AuthManager(
        apiClient: LiveAuthAPIClient(baseURL: AppConfiguration.apiBaseURL),
        tokenStorage: KeychainTokenStorage()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .task { await authManager.bootstrap() }
        }
    }
}
