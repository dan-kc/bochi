import SwiftUI

// Shared small pill used in list rows.
struct EntityListMetaPill: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.entityListColorStrategy) private var colorStrategy

    let text: String
    let isSet: Bool
    var role: BochiThemeRole = .neutral

    private var textColor: Color {
        if colorStrategy.usesRolePalette || isSet {
            return theme.lowContrastText(for: role)
        }

        return theme.lowContrastText(for: .neutral)
    }

    private var borderColor: Color {
        colorStrategy.interactiveBorder(for: role, theme: theme, isRoleSelected: isSet)
    }

    private var backgroundColor: Color {
        colorStrategy.componentBackground(for: role, theme: theme, isRoleSelected: isSet)
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .contentTransition(.identity)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
    }
}
