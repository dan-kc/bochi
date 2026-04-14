import SwiftUI

struct TradesView: View {
    var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle("Trades")
        }
    }
}

#Preview {
    TradesView()
        .environment(BalanceStore())
}
