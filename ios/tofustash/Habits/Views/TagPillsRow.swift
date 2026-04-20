import SwiftUI

// Displays colored tag pills for tags applied to a habit.
// Each pill uses the tag's hex color as background with white text.
// The entire section is tappable — not individual tags. This is like
// wrapping a whole <div> in React with a single onClick handler rather
// than putting onClick on each child element.
struct TagPillsRow: View {
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
    private let fadeWidth: CGFloat = 24

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(size.font)
                        .fontWeight(.medium)
                        .padding(.horizontal, size.horizontalPadding)
                        .padding(.vertical, size.verticalPadding)
                        .background(Color(hex: tag.colorHex).opacity(0.85))
                        .foregroundStyle(.white)
                        // Capsule shape = fully rounded pill, like borderRadius: 999 in CSS
                        .clipShape(Capsule())
                }
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, fadeWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [.white, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
            }
        }
    }
}
