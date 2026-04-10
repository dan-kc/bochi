import SwiftUI

// @main is the app entry point — like ReactDOM.createRoot(...).render(<App />).
@main
struct tofustashApp: App {
    // @State is like useState, but for the component's own lifecycle.
    // AuthManager is marked @Observable, which works like a fine-grained
    // Zustand/Jotai store: SwiftUI tracks which properties each view reads
    // and only re-renders views that depend on the specific property that changed.
    // Unlike React, there's no need for selectors or memo — it's automatic.
    @State private var authManager = AuthManager(
        apiClient: LiveAuthAPIClient(baseURL: AppConfiguration.apiBaseURL),
        tokenStorage: KeychainTokenStorage()
    )

    // HabitStore follows the same pattern as AuthManager — an @Observable class
    // injected into the environment so all child views can access it via
    // @Environment(HabitStore.self). Like creating a second context provider.
    @State private var habitStore = HabitStore()

    // `body` is like the render function — SwiftUI calls it to get the view tree.
    var body: some Scene {
        // WindowGroup is roughly <StrictMode><App /></StrictMode> — the root container.
        WindowGroup {
            ContentView()
                // .environment() is React Context. This is like wrapping in
                // <AuthContext.Provider value={authManager}>. Child views
                // access it with @Environment, which is useContext().
                .environment(authManager)
                .environment(habitStore)
                // .task is useEffect with an empty dep array — runs once on mount.
                // `await` is native here; no need for the async-function-inside-useEffect pattern.
                .task { await authManager.bootstrap() }
        }
    }
}
