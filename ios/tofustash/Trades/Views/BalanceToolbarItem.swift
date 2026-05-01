import SwiftUI

// Displays the user's tofu balance as an overlay, positioned at the top-right
// of the screen. Rendered ONCE in ContentView so it persists across tab switches
// without being destroyed/recreated (which would trigger re-render animations).
//
// In React terms, this is like rendering a fixed-position element at the app
// root rather than inside each route's layout. The balance floats above all
// tab content and never unmounts.
//
// Uses `.contentTransition(.numericText())` for the rolling digit animation
// when the balance changes (e.g., after claiming a reward). Since this view
// is never destroyed, the transition only fires on actual balance changes —
// not on navigation events.
struct BalanceOverlay: View {
    @Environment(BalanceStore.self) private var balanceStore
    @State private var showingTradeHistory = false

    var body: some View {
        Button {
            // Behaviour: tapping the balance opens the full trade history from
            // the bottom, so the user can inspect every tofu gain/spend event
            // without switching to a dedicated tab.
            showingTradeHistory = true
        } label: {
            HStack(spacing: 6) {
                Text("\(balanceStore.balance)")
                    .contentTransition(.numericText())

                Image(systemName: "cube.fill")
            }
            .font(.headline.weight(.semibold))
        }
        .tofuGlassButton(tint: .teal)
        .animation(.easeInOut(duration: 2.0), value: balanceStore.balance)
        .sheet(isPresented: $showingTradeHistory) {
            TradeHistorySheetView(filter: .all)
        }
    }
}
