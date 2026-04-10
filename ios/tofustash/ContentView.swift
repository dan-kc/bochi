import SwiftUI

// `struct ... : View` — a SwiftUI view. Think of it as a React FC. `View` is a protocol (like a TS interface / Rust trait).
struct ContentView: View {
    // `body` — the render method. `some View` is an opaque return type (like Rust's `impl View` — the compiler infers the concrete type)
    var body: some View {
        // SwiftUI uses declarative builder syntax — each nested block is like JSX children
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
        // `.modifier()` chaining — like wrapping a component: <SidebarAdaptable><TabView>...</TabView></SidebarAdaptable>
        .tabViewStyle(.sidebarAdaptable)
    }
}

// #Preview — Xcode live preview macro (like Storybook stories for components)
#Preview {
    ContentView()
        // .environment() — injects into SwiftUI's environment (exactly like React Context Provider)
        .environment(AuthManager(
            apiClient: LiveAuthAPIClient(baseURL: URL(string: "http://localhost:8501")!),
            tokenStorage: KeychainTokenStorage()
        ))
}
