import SwiftUI

struct RewardsView: View {
    var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle("Rewards")
        }
    }
}

#Preview {
    RewardsView()
        .environment(BalanceStore())
}
