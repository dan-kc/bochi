import SwiftUI

// `struct ... : View` — a SwiftUI view. Think of it as a React FC. `View` is a protocol (like a TS interface / Rust trait).
struct ContentView: View {
    // `body` — the render method. `some View` is an opaque return type (like Rust's `impl View` — the compiler infers the concrete type)
    var body: some View {
        // SwiftUI uses declarative builder syntax — each nested block is like JSX children
        // ZStack layers the balance overlay on top of the TabView.
        // The overlay is rendered once and persists across tab switches —
        // no destroy/recreate cycle, so no re-render animations.
        // Like a fixed-position element in CSS above the router outlet.
        ZStack(alignment: .topTrailing) {
            TabView {
                Tab("Habits", systemImage: "checkmark.circle") {
                    HabitsView()
                }
                Tab("Rewards", systemImage: "gift") {
                    RewardsView()
                }
                Tab("Settings", systemImage: "gear") {
                    SettingsView()
                }
            }
            // `.modifier()` chaining — like wrapping a component: <SidebarAdaptable><TabView>...</TabView></SidebarAdaptable>
            .tabViewStyle(.sidebarAdaptable)

            // Balance display — top-right, above all tab content.
            BalanceOverlay()
                .padding(.trailing, 16)
                .padding(.top, 2)
        }
    }
}

// #Preview — Xcode live preview macro (like Storybook stories for components)
#Preview {
    ContentView()
        // .environment() — injects into SwiftUI's environment (exactly like React Context Provider)
        .environment(AuthManager(
            apiClient: AppConfiguration.makeAuthAPIClient(),
            tokenStorage: KeychainTokenStorage()
        ))
        .environment(HabitStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(RewardStore())
        .environment(UserSettingsStore())
}
