import SwiftUI

// Displays colored tag pills for tags applied to a habit.
// Each pill uses the tag's hex color as background with white text.
// The entire section is tappable — not individual tags. This is like
// wrapping a whole <div> in React with a single onClick handler rather
// than putting onClick on each child element.
struct TagPillsRow: View {
    let tags: [Tag]
    var leadingInset: CGFloat = 0
    private let fadeWidth: CGFloat = 24

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
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
