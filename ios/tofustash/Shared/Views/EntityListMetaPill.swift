import SwiftUI

// Shared small pill used in list rows.
struct EntityListMetaPill: View {
    let text: String
    let isSet: Bool

    private var textColor: Color {
        isSet ? .orange : .secondary
    }

    private var borderColor: Color {
        isSet ? .orange : .secondary.opacity(0.6)
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .contentTransition(.identity)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}
