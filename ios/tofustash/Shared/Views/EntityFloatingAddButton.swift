import SwiftUI

// Shared add button so the main tabs keep the same affordance without each
// screen restyling the exact same floating action button.
struct EntityFloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.blue, in: .circle)
                .shadow(radius: 4)
        }
        .padding()
    }
}
