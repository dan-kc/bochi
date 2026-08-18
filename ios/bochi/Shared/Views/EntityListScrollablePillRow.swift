import SwiftUI

// The list rows render form-matching detail items and applied tags in one
// horizontal strip so the user only has one place to scan for summary details.
struct EntityListScrollablePillRow: View {
    let pills: [EntityListRowPill]
    let role: BochiThemeRole
    var leadingInset: CGFloat = 0
    var showsTrailingFade = false
    var trailingFadeInset: CGFloat = 0

    private let verticalBleed: CGFloat = 4

    var body: some View {
        HorizontalFadeScrollRow(
            leadingInset: leadingInset,
            showsTrailingFade: showsTrailingFade,
            trailingFadeInset: trailingFadeInset,
            content: HStack(spacing: 8) {
                ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                    EntityListScrollablePill(pill: pill, role: role)
                }
            }
            .padding(.vertical, verticalBleed)
        )
        // Behaviour: tags draw their capsule outside text bounds, so the
        // scroll row gets bleed room to avoid clipping while parent row
        // spacing still matches rows that have no tags.
        .padding(.vertical, -verticalBleed)
    }
}

private struct EntityListScrollablePill: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.entityListColorStrategy) private var colorStrategy

    let pill: EntityListRowPill
    let role: BochiThemeRole

    var body: some View {
        switch pill {
        case .formItem(let item):
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.caption.weight(item.isSet ? .medium : .regular))

                Text(item.label)
                    .font(.caption)
            }
            .fontWeight(item.isSet ? .medium : .regular)
            .foregroundStyle(colorStrategy.secondaryText(for: .neutral, theme: theme))
            .opacity(item.isSet ? 1 : 0.58)
            .lineLimit(1)
        case .tag(let tag):
            EntityListScrollableTagPill(tag: tag, role: role)
        }
    }
}

private struct EntityListScrollableTagPill: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.entityListColorStrategy) private var colorStrategy

    let tag: Tag
    let role: BochiThemeRole

    var body: some View {
        let style = EntityListTagPillStyle.style(
            for: tag,
            role: role,
            colorStrategy: colorStrategy
        )

        Text(tag.name)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundStyle(style.foregroundColor(theme: theme))
            .padding(.horizontal, 10)
            .background {
                // Behaviour: tags keep their capsule treatment without making
                // the detail row taller than rows that only show field values.
                Capsule()
                    .fill(style.backgroundColor(theme: theme))
                    .padding(.vertical, -4)
            }
            .overlay {
                if style.showsBorder {
                    Capsule()
                        .strokeBorder(theme.interactiveBorder(for: role), lineWidth: 1)
                        .padding(.vertical, -4)
                }
            }
    }
}

enum EntityListTagPillColorSource: Equatable {
    case tag(colorHex: String)
    case role(BochiThemeRole)
}

struct EntityListTagPillStyle: Equatable {
    let colorSource: EntityListTagPillColorSource
    let showsBorder: Bool

    func backgroundColor(theme: BochiTheme) -> Color {
        switch colorSource {
        case .tag(let colorHex):
            BochiTheme.tagBackgroundColor(hex: colorHex)
        case .role(let role):
            theme.componentBackground(for: role)
        }
    }

    func foregroundColor(theme: BochiTheme) -> Color {
        switch colorSource {
        case .tag(let colorHex):
            theme.tagForegroundColor(hex: colorHex)
        case .role(let role):
            theme.lowContrastText(for: role)
        }
    }

    static func style(
        for tag: Tag,
        role _: BochiThemeRole,
        colorStrategy _: EntityListColorStrategy
    ) -> EntityListTagPillStyle {
        EntityListTagPillStyle(
            colorSource: .tag(colorHex: tag.colorHex),
            showsBorder: false
        )
    }
}
