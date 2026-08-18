import SwiftUI

// Shared action chrome for the compact row pills and expanded form buttons.
// Keeping the surfaces together lets the list rows avoid nested SwiftUI
// Buttons while still preserving disabled and accessibility behaviour.
struct BochiActionSurface<Label: View>: View {
    @Environment(\.bochiTheme) private var theme
    enum Layout {
        case compact
        case compactEntity(BochiThemeRole)
        case compactEntityOnNeutral(BochiThemeRole)
        case compactOnNeutral(foreground: Color)
        case expanded(tint: Color?)
        case expandedPremium
        case expandedEntity(BochiThemeRole)
        case expandedEntityOnNeutral(BochiThemeRole)
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
            compactSurface(
                background: theme.componentBackground(),
                border: theme.subtleBorder()
            )
        case .compactEntity(let role):
            compactSurface(
                background: theme.componentBackground(),
                border: nil,
                foreground: theme.accentSolidFill(for: role)
            )
        case .compactEntityOnNeutral(let role):
            compactSurface(
                background: theme.componentBackground(for: .neutral),
                border: theme.subtleBorder(for: .neutral),
                foreground: theme.accentSolidFill(for: role)
            )
        case .compactOnNeutral(let foreground):
            compactSurface(
                background: theme.componentBackground(for: .neutral),
                border: theme.subtleBorder(for: .neutral),
                foreground: foreground
            )
        case .expanded(let tint):
            Button(action: action) {
                label
            }
            .expandedButtonStyle(tint: tint)
            .controlSize(.large)
            .disabled(!isEnabled)
        case .expandedPremium:
            expandedPremiumSurface()
        case .expandedEntity(let role):
            expandedEntitySurface(
                foregroundRole: role,
                backgroundRole: role,
                border: theme.accentInteractiveBorder(for: role)
            )
        case .expandedEntityOnNeutral(let role):
            expandedEntitySurface(
                foregroundRole: role,
                backgroundRole: .neutral,
                border: theme.subtleBorder(for: .neutral)
            )
        }
    }

    private func expandedPremiumSurface() -> some View {
        Button(action: action) {
            label
                .foregroundStyle(theme.premiumText())
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(theme.premiumBackground(), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(theme.premiumFill(), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private func expandedEntitySurface(
        foregroundRole: BochiThemeRole,
        backgroundRole: BochiThemeRole,
        border: Color?
    ) -> some View {
        Button(action: action) {
            label
                .foregroundStyle(theme.accentSolidFill(for: foregroundRole))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(theme.accentComponentBackground(for: backgroundRole), in: Capsule())
                .overlay {
                    if let border {
                        Capsule()
                            .stroke(border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private func compactSurface(
        background: Color,
        border: Color?,
        foreground: Color? = nil
    ) -> some View {
        Button(action: action) {
            label
                .foregroundStyle(foreground ?? theme.primaryText())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(background, in: Capsule())
                .overlay {
                    if let border {
                        Capsule()
                            .stroke(border, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityHint(isEnabled ? "" : "Unavailable")
    }
}

private extension View {
    @ViewBuilder
    func expandedButtonStyle(tint: Color?) -> some View {
        if let tint {
            bochiGlassButton(tint: tint)
        } else {
            bochiGlassButton(tint: BochiTheme.solidFill(palette: .paper))
        }
    }

}
