import SwiftUI
import UIKit

struct EntityListRowText: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.entityListColorStrategy) private var colorStrategy

    let name: String
    let description: String
    let metadataItems: [EntityListRowMetadataItem]
    let metadataSpacing: CGFloat
    let pills: [EntityListRowPill]
    let role: BochiThemeRole
    let isNameStruckThrough: Bool
    let showsDetails: Bool

    private let descriptionFadeWidth: CGFloat = 24
    private let singleLineTextMinimumHeight: CGFloat = 34
    private let singleLineTextVerticalOffset: CGFloat = 2

    init(
        name: String,
        description: String,
        metadataItems: [EntityListRowMetadataItem] = [],
        metadataSpacing: CGFloat = 8,
        pills: [EntityListRowPill],
        role: BochiThemeRole,
        isNameStruckThrough: Bool = false,
        showsDetails: Bool = false
    ) {
        self.name = name
        self.description = description
        self.metadataItems = metadataItems
        self.metadataSpacing = metadataSpacing
        self.pills = pills
        self.role = role
        self.isNameStruckThrough = isNameStruckThrough
        self.showsDetails = showsDetails
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !metadataItems.isEmpty {
                metadataRow
            }

            nameText

            if let rowDescription {
                descriptionText(rowDescription)
            }

            if showsDetails && !pills.isEmpty {
                EntityListScrollablePillRow(
                    pills: pills,
                    role: role,
                    leadingInset: 16,
                    showsTrailingFade: true,
                    trailingFadeInset: 0
                )
                .padding(.leading, -16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Behaviour: when the row has only a title, center it against the
        // trailing action control instead of bottom-aligning the shorter text.
        .frame(maxWidth: .infinity, minHeight: minimumTextStackHeight, alignment: .leading)
        .offset(y: verticalTextOffset)
    }

    private var textRole: BochiThemeRole {
        .neutral
    }

    private var rowDescription: EntityListRowDescription? {
        EntityListRowDescriptionSupport.description(from: description)
    }

    private var minimumTextStackHeight: CGFloat? {
        hasSupportingContent ? nil : singleLineTextMinimumHeight
    }

    private var verticalTextOffset: CGFloat {
        hasSupportingContent ? 0 : singleLineTextVerticalOffset
    }

    private var hasSupportingContent: Bool {
        !metadataItems.isEmpty || rowDescription != nil || (showsDetails && !pills.isEmpty)
    }

    private var metadataRow: some View {
        HStack(spacing: metadataSpacing) {
            ForEach(metadataItems) { item in
                metadataItem(item)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(colorStrategy.secondaryText(for: textRole, theme: theme))
        .lineLimit(1)
    }

    @ViewBuilder
    private var nameText: some View {
        let text = Group {
            if isNameStruckThrough {
                struckNameText
            } else {
                Text(name)
                    .lineLimit(1)
            }
        }
        .font(.body)
        .foregroundStyle(colorStrategy.primaryText(for: textRole, theme: theme))

        text
    }

    private func metadataItem(_ item: EntityListRowMetadataItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .imageScale(.small)
                .frame(width: 12)

            if let label = item.label {
                Text(label)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var struckNameText: some View {
        ZStack(alignment: .leading) {
            Text(name)
                .lineLimit(1)
                .hidden()

            GeometryReader { proxy in
                let renderedName = EntityListNameTruncationSupport.renderedName(
                    name,
                    availableWidth: proxy.size.width,
                    font: .preferredFont(forTextStyle: .body)
                )

                HStack(spacing: 0) {
                    Text(renderedName.struckText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .overlay(alignment: .center) {
                            // Behaviour: completed rows cross out the task
                            // text itself, but leave a manually added
                            // truncation ellipsis readable.
                            Rectangle()
                                .fill(colorStrategy.primaryText(for: textRole, theme: theme).opacity(0.72))
                                .frame(height: 1)
                                .accessibilityHidden(true)
                        }

                    if renderedName.showsEllipsis {
                        Text(EntityListNameTruncationSupport.ellipsis)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .allowsHitTesting(false)
        }
    }

    private func descriptionText(_ rowDescription: EntityListRowDescription) -> some View {
        Text(rowDescription.text)
            .font(.caption)
            .foregroundStyle(colorStrategy.secondaryText(for: textRole, theme: theme))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [theme.primaryText(), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: descriptionFadeWidth)
                }
            }
    }
}

struct EntityListRowDescription: Equatable {
    let text: String
}

enum EntityListRowDescriptionSupport {
    static func description(from description: String) -> EntityListRowDescription? {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else { return nil }

        return EntityListRowDescription(text: trimmedDescription)
    }
}

struct EntityListRenderedName: Equatable {
    let struckText: String
    let showsEllipsis: Bool
}

enum EntityListNameTruncationSupport {
    static let ellipsis = "..."
    private static let truncationTolerance: CGFloat = 0.5

    static func renderedName(
        _ name: String,
        availableWidth: CGFloat,
        font: UIFont
    ) -> EntityListRenderedName {
        guard availableWidth > 0 else {
            return EntityListRenderedName(struckText: "", showsEllipsis: true)
        }

        if textWidth(name, font: font) <= availableWidth + truncationTolerance {
            return EntityListRenderedName(struckText: name, showsEllipsis: false)
        }

        let targetWidth = max(0, availableWidth - textWidth(ellipsis, font: font))
        let characters = Array(name)
        var lowerBound = 0
        var upperBound = characters.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound + 1) / 2
            let candidate = String(characters.prefix(midpoint))

            if textWidth(candidate, font: font) <= targetWidth + truncationTolerance {
                lowerBound = midpoint
            } else {
                upperBound = midpoint - 1
            }
        }

        return EntityListRenderedName(
            struckText: String(characters.prefix(lowerBound)),
            showsEllipsis: true
        )
    }

    private static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
