import SwiftUI

struct HabitsView: View {
    var body: some View {
        NavigationStack {
            // Color.clear — placeholder empty view (like returning <></> in React with a title set)
            Color.clear
                .navigationTitle("Habits")
        }
    }
}

#Preview {
    HabitsView()
}
