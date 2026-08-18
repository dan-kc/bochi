import SwiftUI

// Reusable control strip for entity lists. Sort stays as a menu, while every
// other chip is an inline visibility toggle.
struct EntityListControls: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    let preferences: EntityListPreferences
    let tagScope: EntityListTagScope
    let availableTags: [Tag]
    let statusFilters: [EntityListStatusFilter]
    let isEnabled: Bool
    var showsSort: Bool = true
    let onSelectSort: (EntityListSortOption) -> Void
    let onToggleStatus: (EntityListStatusFilter) -> Void
    let onToggleTag: (RecordID) -> Void
    var onToggleTaskGroup: (() -> Void)? = nil
    var onToggleTaskCompletion: ((EntityListStatusFilter) -> Void)? = nil

    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil

    private var controlItems: [EntityListControlItem] {
        if tagScope == .search {
            return [
                .status(.taskGroup),
                .status(.reward),
                .status(.task),
                .status(.recurringTask),
                .status(.completed),
                .status(.hidden),
                .status(.locked)
            ] + availableTags.map(EntityListControlItem.tag)
        }

        if tagScope == .earn {
            return [
                .status(.task),
                .status(.recurringTask),
                .status(.hidden),
                .status(.locked)
            ] + availableTags.map(EntityListControlItem.tag)
        }

        return statusFilters.map(EntityListControlItem.status) + availableTags.map(EntityListControlItem.tag)
    }

    private var animationSignature: [String] {
        [
            "scope:\(tagScope)",
            "sort:\(effectiveSort.rawValue)"
        ] + controlItems.map { item in
            switch item {
            case .status(let status):
                return "status:\(status.rawValue):\(preferences.showsStatus(status))"
            case .tag(let tag):
                return "tag:\(tag.id.rawValue):\(tag.name):\(tag.colorHex):\(preferences.showsTag(tag.id))"
            }
        } + [
            "earn.complete:\(preferences.showsStatus(.completed))",
            "earn.incomplete:\(preferences.showsStatus(.incomplete))"
        ]
    }

    private var usesDamageTerminology: Bool {
        tagScope == .rewards
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }

    private var effectiveSort: EntityListSortOption {
        preferences.effectiveSort(hasPremiumAccess: hasPremiumAccess)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showsSort {
                    sortButton
                }

                ForEach(controlItems) { item in
                    controlButton(item)
                        .transition(transition(for: item))
                        .zIndex(zIndex(for: item))
                }
            }
            .padding(.horizontal, 16)
            // Behaviour: changing list tabs should feel like the same control
            // strip receiving new props, so filters enter and leave the row
            // instead of the whole bar blinking into a fresh layout.
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: animationSignature)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Behaviour: while the user is reading farther down the list, freeze the
        // buttons so an accidental tap cannot reorder the content and make them
        // lose their place.
        .allowsHitTesting(isEnabled)
        .fullScreenCover(item: $premiumUpsellFeature) { feature in
            PremiumUpsellView(feature: feature)
        }
    }

    private var sortButton: some View {
        Menu {
            ForEach(EntityListSortOption.allCases) { option in
                Button {
                    selectSort(option)
                } label: {
                    HStack {
                        Text("\(option.menuFieldLabel(usesDamageTerminology: usesDamageTerminology)) \(option.directionLabel)")

                        if option == effectiveSort {
                            Image(systemName: "checkmark")
                        }

                        if option.isPremiumOnly && !hasPremiumAccess {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(theme.premiumText())
                        }
                    }
                }
                .accessibilityLabel(sortAccessibilityLabel(for: option))
            }
        } label: {
            HStack(spacing: 6) {
                Text(effectiveSort.fieldLabel(usesDamageTerminology: usesDamageTerminology))
                    .font(.callout.weight(.medium))
                    .contentTransition(.opacity)

                Text(effectiveSort.directionArrow)
                    .font(.callout.weight(.semibold))
                    .contentTransition(.opacity)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .entityListSortSurface(isHighlighted: effectiveSort != .priceHighToLow, showsBorder: true, theme: theme)
        .accessibilityLabel("\(effectiveSort.fieldLabel(usesDamageTerminology: usesDamageTerminology)) \(effectiveSort.directionLabel)")
    }

    private func selectSort(_ option: EntityListSortOption) {
        guard hasPremiumAccess || !option.isPremiumOnly else {
            premiumUpsellFeature = .sorting
            return
        }

        onSelectSort(option)
    }

    private func sortAccessibilityLabel(for option: EntityListSortOption) -> String {
        var parts = [
            option.menuFieldLabel(usesDamageTerminology: usesDamageTerminology),
            option.directionLabel
        ]

        if option == effectiveSort {
            parts.append("Selected")
        }

        if option.isPremiumOnly && !hasPremiumAccess {
            parts.append("Premium")
        }

        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func controlButton(_ item: EntityListControlItem) -> some View {
        switch item {
        case .status(let status):
            statusToggleButton(status)
        case .tag(let tag):
            tagToggleButton(tag)
        }
    }

    private func transition(for item: EntityListControlItem) -> AnyTransition {
        let horizontalOffset: CGFloat = {
            switch item {
            case .status:
                return -10
            case .tag:
                return 14
            }
        }()

        return .asymmetric(
            insertion: .modifier(
                active: EntityListControlTransitionModifier(
                    opacity: 0,
                    scale: 0.94,
                    xOffset: horizontalOffset
                ),
                identity: EntityListControlTransitionModifier()
            )
            .animation(.easeOut(duration: 0.24).delay(0.2)),
            removal: .modifier(
                active: EntityListControlTransitionModifier(
                    opacity: 0,
                    scale: 0.96,
                    xOffset: horizontalOffset * -0.65
                ),
                identity: EntityListControlTransitionModifier()
            )
            .animation(.easeIn(duration: 0.16))
        )
    }

    private func zIndex(for item: EntityListControlItem) -> Double {
        switch item {
        case .status:
            return 0
        case .tag:
            return 1
        }
    }

    private func statusToggleButton(_ status: EntityListStatusFilter) -> some View {
        if tagScope == .earn && status == .task {
            return AnyView(earnTaskToggleButton)
        }

        return AnyView(standardStatusToggleButton(status))
    }

    private func standardStatusToggleButton(_ status: EntityListStatusFilter) -> some View {
        let isSelected = preferences.showsStatus(status)

        return Button {
            withAnimation(.default) {
                onToggleStatus(status)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.callout.weight(.medium))

                Text(status.label)
                    .font(.callout)
                    .contentTransition(.opacity)
            }
            .entityListToggleSurface(isSelected: isSelected, theme: theme)
        }
        .accessibilityLabel("\(status.label), \(isSelected ? "Shown" : "Hidden")")
        .buttonStyle(.plain)
    }

    private var earnTaskToggleButton: some View {
        let isSelected = preferences.showsStatus(.task)

        return HStack(spacing: 0) {
            Button {
                withAnimation(.default) {
                    (onToggleTaskGroup ?? { onToggleStatus(.task) })()
                }
            } label: {
                Text(EntityListStatusFilter.task.label)
                    .font(.callout)
                    .contentTransition(.opacity)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)

            earnTaskCompletionButton(.completed)
            earnTaskCompletionButton(.incomplete)
        }
        .foregroundStyle(isSelected ? theme.primaryText() : theme.secondaryText())
        .background(
            isSelected ? theme.selectedBackground(for: .neutral) : theme.componentBackground(),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.strongBorder(for: .neutral), lineWidth: 1)
            }
        }
        .opacity(isSelected ? 1 : 0.9)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task, \(isSelected ? "Shown" : "Hidden")")
    }

    private func earnTaskCompletionButton(_ status: EntityListStatusFilter) -> some View {
        let taskIsSelected = preferences.showsStatus(.task)
        let isSelected = taskIsSelected && preferences.showsStatus(status)

        return Button {
            withAnimation(.default) {
                (onToggleTaskCompletion ?? onToggleStatus)(status)
            }
        } label: {
            Text(status == .completed ? "Complete" : "Incomplete")
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 5)
                .frame(height: 32)
                .foregroundStyle(isSelected ? theme.primaryText() : theme.secondaryText())
                .background(
                    isSelected ? theme.componentBackground() : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.subtleBorder(), lineWidth: 1)
                }
        }
        .accessibilityLabel("\(status.label), \(isSelected ? "Shown" : "Hidden")")
        .buttonStyle(.plain)
    }

    private func tagToggleButton(_ tag: Tag) -> some View {
        let isSelected = preferences.showsTag(tag.id)

        return Button {
            withAnimation(.default) {
                onToggleTag(tag.id)
            }
        } label: {
            Text(tag.name)
                .font(.callout)
                .contentTransition(.opacity)
                .entityListToggleSurface(
                    isSelected: isSelected,
                    theme: theme,
                    selectedForegroundColor: theme.tagForegroundColor(hex: tag.colorHex),
                    selectedBackgroundColor: BochiTheme.tagBackgroundColor(hex: tag.colorHex),
                    selectedBorderColor: theme.tagForegroundColor(hex: tag.colorHex).opacity(0.35)
                )
        }
        .accessibilityLabel("\(tag.name), \(isSelected ? "Shown" : "Hidden")")
        .buttonStyle(.plain)
    }
}

private enum EntityListControlItem: Identifiable {
    case status(EntityListStatusFilter)
    case tag(Tag)

    var id: String {
        switch self {
        case .status(let status):
            return "status.\(status.rawValue)"
        case .tag(let tag):
            return "tag.\(tag.id.rawValue)"
        }
    }
}

private struct EntityListControlTransitionModifier: ViewModifier {
    var opacity: Double = 1
    var scale: CGFloat = 1
    var xOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(x: xOffset)
    }
}

extension View {
    func entityListToggleSurface(
        isSelected: Bool,
        theme: BochiTheme,
        selectedForegroundColor: Color? = nil,
        selectedBackgroundColor: Color? = nil,
        selectedBorderColor: Color? = nil
    ) -> some View {
        let selectedForegroundColor = selectedForegroundColor ?? theme.primaryText()
        let selectedBackgroundColor = selectedBackgroundColor ?? theme.selectedBackground(for: .neutral)
        let selectedBorderColor = selectedBorderColor ?? theme.strongBorder(for: .neutral)

        return foregroundStyle(isSelected ? selectedForegroundColor : theme.secondaryText())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? selectedBackgroundColor : theme.componentBackground(),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selectedBorderColor, lineWidth: 1)
                }
            }
            .opacity(isSelected ? 1 : 0.9)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func bochiControlPillSurface(isHighlighted: Bool, showsBorder: Bool, theme: BochiTheme) -> some View {
        bochiControlPillSurface(
            foregroundColor: isHighlighted ? theme.primaryText() : theme.secondaryText(),
            backgroundColor: isHighlighted ? theme.selectedBackground(for: .neutral) : theme.componentBackground(),
            borderColor: theme.strongBorder(for: .neutral),
            showsBorder: showsBorder,
            isFaded: false
        )
    }

    func bochiControlPillSurface(
        foregroundColor: Color,
        backgroundColor: Color,
        borderColor: Color,
        showsBorder: Bool,
        isFaded: Bool
    ) -> some View {
        foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor, in: Capsule())
            .overlay {
                if showsBorder {
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 1)
                }
            }
            .opacity(isFaded ? 0.55 : 1)
    }

    func entityListSortSurface(isHighlighted: Bool, showsBorder: Bool, theme: BochiTheme) -> some View {
        foregroundStyle(isHighlighted ? theme.primaryText() : theme.secondaryText())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isHighlighted ? theme.selectedBackground(for: .neutral) : theme.componentBackground(),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.subtleBorder(), lineWidth: 1)
                }
            }
    }
}
