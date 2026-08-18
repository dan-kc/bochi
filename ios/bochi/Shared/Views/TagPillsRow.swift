import SwiftUI

// Displays colored tag pills for tags applied to a recurringTask.
// Each pill resolves the saved tag color through the current light/dark theme.
// The entire section is tappable — not individual tags. This is like
// wrapping a whole <div> in React with a single onClick handler rather
// than putting onClick on each child element.
struct TagPillsRow: View {
    @Environment(\.bochiTheme) private var theme
    enum Size {
        case compact
        case form

        var font: Font {
            switch self {
            case .compact:
                .caption
            case .form:
                .subheadline
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact:
                10
            case .form:
                14
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact:
                4
            case .form:
                8
            }
        }
    }

    let tags: [Tag]
    var size: Size = .compact
    var leadingInset: CGFloat = 0
    var showsTrailingFade = false
    var trailingFadeInset: CGFloat = 0

    var body: some View {
        HorizontalFadeScrollRow(
            leadingInset: leadingInset,
            showsTrailingFade: showsTrailingFade,
            trailingFadeInset: trailingFadeInset,
            content: HStack(spacing: 8) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(size.font)
                        .fontWeight(.medium)
                        .padding(.horizontal, size.horizontalPadding)
                        .padding(.vertical, size.verticalPadding)
                        .background(BochiTheme.tagBackgroundColor(hex: tag.colorHex))
                        .foregroundStyle(theme.tagForegroundColor(hex: tag.colorHex))
                        // Capsule shape = fully rounded pill, like borderRadius: 999 in CSS
                        .clipShape(Capsule())
                }
            }
        )
    }
}
