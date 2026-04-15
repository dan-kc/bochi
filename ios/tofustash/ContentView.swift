import SwiftUI

// `struct ... : View` — a SwiftUI view. Think of it as a React FC. `View` is a protocol (like a TS interface / Rust trait).
struct ContentView: View {
    @State private var habitFormPresenter = HabitFormPresenter()

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
                Tab("Trades", systemImage: "arrow.left.arrow.right") {
                    TradesView()
                }
                Tab("Settings", systemImage: "gear") {
                    SettingsView()
                }
            }
            // `.modifier()` chaining — like wrapping a component: <SidebarAdaptable><TabView>...</TabView></SidebarAdaptable>
            .tabViewStyle(.sidebarAdaptable)
            .environment(habitFormPresenter)
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // Balance display — top-right, above all tab content.
            BalanceOverlay()
                .padding(.trailing, 16)
                .padding(.top, 2)

            if let route = habitFormPresenter.route {
                habitFormOverlay(route: route)
                    .zIndex(10)
                    .transition(.identity)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: habitFormPresenter.route == nil)
        .environment(habitFormPresenter)
    }

    @ViewBuilder
    private func habitFormOverlay(route: HabitFormPresenter.Route) -> some View {
        switch route {
        case .new(let prefill, let onDiscard):
            HabitFormModal(
                mode: .new,
                initialFocus: .name,
                prefill: prefill,
                onDiscard: onDiscard,
                onDelete: nil,
                onClose: {
                    habitFormPresenter.dismiss()
                }
            )
        case .change(let habit, let focus, let onDelete):
            HabitFormModal(
                mode: .change(habit),
                initialFocus: focus,
                prefill: nil,
                onDiscard: nil,
                onDelete: onDelete,
                onClose: {
                    habitFormPresenter.dismiss()
                }
            )
        }
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
        .environment(HabitStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(BalanceStore())
        .environment(UserSettingsStore())
        .environment(HabitFormPresenter())
}
