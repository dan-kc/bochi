import SwiftUI

// Shared small pill used in list rows. The animation is the same attention
// affordance already used in habits: incomplete fields pulse subtly so users
// learn what still affects pricing.
struct EntityListMetaPill: View {
    let text: String
    let isSet: Bool
    let animating: Bool

    @State private var isHighlighted = false

    private var shouldAnimateAttention: Bool {
        animating && !isSet
    }

    private var textColor: Color {
        guard isSet else {
            if animating {
                return isHighlighted ? .gray.opacity(0.72) : .secondary
            }
            return .secondary
        }

        return .orange
    }

    private var borderColor: Color {
        guard isSet else {
            if animating {
                return isHighlighted ? .gray.opacity(0.72) : .secondary.opacity(0.6)
            }
            return .secondary.opacity(0.6)
        }

        return .orange
    }

    private var glowColor: Color {
        animating && !isSet && isHighlighted ? .white.opacity(0.18) : .clear
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
            .shadow(color: glowColor, radius: 8)
            .animation(
                shouldAnimateAttention
                    ? .easeInOut(duration: 1.15).repeatForever(autoreverses: true)
                    : .easeInOut(duration: 0.2),
                value: isHighlighted
            )
            .animation(nil, value: text)
            .animation(nil, value: isSet)
            .onAppear {
                guard shouldAnimateAttention else {
                    isHighlighted = false
                    return
                }

                isHighlighted = false
                DispatchQueue.main.async {
                    isHighlighted = true
                }
            }
            .onChange(of: animating) { _, newValue in
                if newValue && !isSet {
                    isHighlighted = false
                    DispatchQueue.main.async {
                        isHighlighted = true
                    }
                } else {
                    isHighlighted = false
                }
            }
            .onChange(of: isSet) { _, newValue in
                if newValue {
                    isHighlighted = false
                }
            }
    }
}
