import SwiftUI

// Displays the user's points balance as an overlay, positioned at the top-right
// of the screen. Rendered ONCE in ContentView so it persists across tab switches
// without being destroyed/recreated (which would trigger re-render animations).
//
// In React terms, this is like rendering a fixed-position element at the app
// root rather than inside each route's layout. The balance floats above all
// tab content and never unmounts.
//
// Uses `.contentTransition(.numericText())` for the rolling digit animation
// when the balance changes (e.g., after completing a recurringTask). Since this view
// is never destroyed, the transition only fires on actual balance changes —
// not on navigation events.
struct BalanceOverlay: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(BalanceStore.self) private var balanceStore
    @State private var showingTradeHistory = false

    var body: some View {
        Button {
            // Behaviour: tapping the balance opens the full trade history from
            // the bottom, so the user can inspect every point gain/spend event
            // without switching to a dedicated tab.
            showingTradeHistory = true
        } label: {
            PointsAmountLabel(text: "\(balanceStore.balance)")
                .contentTransition(.numericText())
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.secondaryText())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.componentBackground(), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 2.0), value: balanceStore.balance)
        .sheet(isPresented: $showingTradeHistory) {
            TradeHistorySheetView(filter: .all)
        }
    }
}
