import SwiftUI

// Displays colored tag pills for tags applied to a habit.
// Each pill uses the tag's hex color as background with white text.
// The entire section is tappable — not individual tags. This is like
// wrapping a whole <div> in React with a single onClick handler rather
// than putting onClick on each child element.
struct TagPillsRow: View {
    let tags: [Tag]

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
        }
    }
}
