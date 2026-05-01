import SwiftUI

// Shared amount button for earn/spend actions. This keeps the list rows and
// edit sheets visually aligned without forcing habits and rewards into one
// generic feature model.
struct TofuActionButton: View {
    enum Layout {
        case compact
        case expanded(title: String)
    }

    let amount: Int
    let polarity: Polarity
    let layout: Layout
    let action: () -> Void

    enum Polarity {
        case earning
        case spending

        var prefix: String {
            switch self {
            case .earning:
                return "+"
            case .spending:
                return "-"
            }
        }

        var icon: String { "cube.fill" }

        var tint: Color {
            switch self {
            case .earning:
                return .green
            case .spending:
                return .orange
            }
        }
    }

    var body: some View {
        switch layout {
        case .compact:
            compactActionSurface
        case .expanded(let title):
            Button(action: action) {
                expandedLabel(title: title)
            }
            .tofuGlassButton(tint: polarity.tint)
            .controlSize(controlSize)
        }
    }

    private var compactActionSurface: some View {
        compactLabel
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
            }
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }

    private var compactLabel: some View {
        HStack(spacing: 6) {
            Text("\(polarity.prefix)\(amount)")
                .contentTransition(.numericText())
            Image(systemName: polarity.icon)
                .font(.caption)
        }
        .font(.callout)
        .fontWeight(.semibold)
    }

    private func expandedLabel(title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                Text("\(polarity.prefix)\(amount)")
                    .contentTransition(.numericText())
                Image(systemName: polarity.icon)
                    .font(.caption)
            }
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    private var controlSize: ControlSize {
        switch layout {
        case .compact:
            return .regular
        case .expanded:
            return .large
        }
    }
}
