import SwiftUI

// Shared action chrome for the compact row pills and expanded form buttons.
// Keeping the surfaces together lets the list rows avoid nested SwiftUI
// Buttons while still preserving disabled and accessibility behaviour.
struct TofuActionSurface<Label: View>: View {
    enum Layout {
        case compact
        case expanded(tint: Color)
    }

    let layout: Layout
    let isEnabled: Bool
    let action: () -> Void
    let label: Label

    init(
        layout: Layout,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.layout = layout
        self.isEnabled = isEnabled
        self.action = action
        self.label = label()
    }

    var body: some View {
        switch layout {
        case .compact:
            compactSurface
        case .expanded(let tint):
            Button(action: action) {
                label
            }
            .tofuGlassButton(tint: tint)
            .controlSize(.large)
            .disabled(!isEnabled)
        }
    }

    private var compactSurface: some View {
        label
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.55)
            // Behaviour: the trailing action pill should win taps over the row's
            // edit gesture, even when the pill is currently disabled.
            .highPriorityGesture(
                TapGesture().onEnded {
                    guard isEnabled else { return }
                    action()
                }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isEnabled ? "" : "Unavailable")
    }
}
