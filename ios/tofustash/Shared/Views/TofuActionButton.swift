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
    var isEnabled: Bool = true
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
            TofuActionSurface(layout: .compact, isEnabled: isEnabled, action: action) {
                compactLabel
            }
        case .expanded(let title):
            TofuActionSurface(
                layout: .expanded(tint: polarity.tint),
                isEnabled: isEnabled,
                action: action
            ) {
                expandedLabel(title: title)
            }
        }
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

}
