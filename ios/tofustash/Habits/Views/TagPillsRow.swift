import SwiftUI

// Displays colored tag pills for tags applied to a habit.
// Each pill uses the tag's hex color as background with white text.
// Tapping any pill triggers the onTap callback (opens the tags view).
//
// In React, this would be a row of <Pressable> components with
// dynamic backgroundColor from the tag's color_hex.
struct TagPillsRow: View {
    let tags: [Tag]
    let onTap: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    Button {
                        onTap()
                    } label: {
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
}
