import SwiftUI

extension EntityListTagScope {
    var themeRole: BochiThemeRole {
        switch self {
        case .search:
            return .neutral
        case .earn:
            return .task
        case .tasks:
            return .task
        case .recurringTasks:
            return .recurringTask
        case .rewards:
            return .reward
        }
    }
}

// Shared list shell for tasks, recurringTasks, and rewards. Each screen keeps its own
// row content and pricing logic, but the list chrome should behave the same:
// controls at the top, controls locked while scrolled down, and a distinct
// empty state when filters hide everything.
struct EntityListScreen<RowID: Hashable, RowContent: View>: View {
    @Environment(\.bochiTheme) private var theme

    // SwiftUI `List` supports a top content margin for reserving space under
    // the floating controls, but still needs a final spacer row for bottom
    // runway above the floating add button.
    private static var bottomContentPadding: CGFloat { 96 }
    private static var topControlsContentMargin: CGFloat { 36 }
    private static var topFadeHiddenControlsHeight: CGFloat { 106 }
    private static var topFadeVisibleControlsExtension: CGFloat { 72 }
    private static var topFadeMaximumOpacity: Double { 0.90 }
    private static var topFadeCurveStrength: Double { 0.65 }
    let hasAnyItems: Bool
    let visibleItemCount: Int
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let filteredEmptyTitle: String
    let filteredEmptyDescription: String
    let preferences: EntityListPreferences
    let tagScope: EntityListTagScope
    let availableTags: [Tag]
    let statusFilters: [EntityListStatusFilter]
    let colorStrategy: EntityListColorStrategy
    let rowIDs: [RowID]
    let onSelectSort: (EntityListSortOption) -> Void
    let onClearFilters: () -> Void
    let onToggleStatus: (EntityListStatusFilter) -> Void
    let onToggleTag: (RecordID) -> Void
    let onControlsVisibilityChange: (Bool) -> Void
    let onPendingScrollCompleted: ((RowID) -> Void)?
    let rowContent: RowContent

    @Binding private var pendingScrollTargetID: RowID?
    @State private var controlsVisibilityTracker = EntityListControlsVisibilityTracker()
    @State private var controlsAreVisible = true

    init(
        hasAnyItems: Bool,
        visibleItemCount: Int,
        emptyTitle: String,
        emptySystemImage: String,
        emptyDescription: String,
        filteredEmptyTitle: String,
        filteredEmptyDescription: String,
        preferences: EntityListPreferences,
        tagScope: EntityListTagScope,
        availableTags: [Tag],
        statusFilters: [EntityListStatusFilter],
        colorStrategy: EntityListColorStrategy = .rolePalette,
        rowIDs: [RowID],
        pendingScrollTargetID: Binding<RowID?>,
        onSelectSort: @escaping (EntityListSortOption) -> Void,
        onClearFilters: @escaping () -> Void,
        onToggleStatus: @escaping (EntityListStatusFilter) -> Void,
        onToggleTag: @escaping (RecordID) -> Void,
        onControlsVisibilityChange: @escaping (Bool) -> Void = { _ in },
        onPendingScrollCompleted: ((RowID) -> Void)? = nil,
        @ViewBuilder rowContent: () -> RowContent
    ) {
        self.hasAnyItems = hasAnyItems
        self.visibleItemCount = visibleItemCount
        self.emptyTitle = emptyTitle
        self.emptySystemImage = emptySystemImage
        self.emptyDescription = emptyDescription
        self.filteredEmptyTitle = filteredEmptyTitle
        self.filteredEmptyDescription = filteredEmptyDescription
        self.preferences = preferences
        self.tagScope = tagScope
        self.availableTags = availableTags
        self.statusFilters = statusFilters
        self.colorStrategy = colorStrategy
        self.rowIDs = rowIDs
        self._pendingScrollTargetID = pendingScrollTargetID
        self.onSelectSort = onSelectSort
        self.onClearFilters = onClearFilters
        self.onToggleStatus = onToggleStatus
        self.onToggleTag = onToggleTag
        self.onControlsVisibilityChange = onControlsVisibilityChange
        self.onPendingScrollCompleted = onPendingScrollCompleted
        self.rowContent = rowContent()
    }

    var body: some View {
        Group {
            if !hasAnyItems {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
            } else {
                ScrollViewReader { scrollProxy in
                    List {
                        listRows
                    }
                    .listStyle(.plain)
                    .listSectionSpacing(0)
                    .contentMargins(.top, Self.topControlsContentMargin, for: .scrollContent)
                    .scrollDismissesKeyboard(.immediately)
                    // Behaviour: the scrolling surface itself also stays transparent,
                    // otherwise iOS paints a white grouped background behind clear rows.
                    .scrollContentBackground(.hidden)
                    // Behaviour: the list can keep its bottom scroll-edge fade,
                    // but the top of entity tabs should not blur the title area.
                    .scrollEdgeEffectHidden(true, for: .top)
                    .animation(.default, value: rowIDs)
                    .onScrollGeometryChange(for: EntityListScrollMetrics.self) { geometry in
                        EntityListScrollMetrics(
                            contentOffsetY: geometry.contentOffset.y,
                            contentTopInset: geometry.contentInsets.top,
                            contentBottomLimitY: max(
                                geometry.contentInsets.top,
                                geometry.contentSize.height
                                    - geometry.containerSize.height
                                    + geometry.contentInsets.bottom
                            )
                        )
                    } action: { _, metrics in
                        updateControlsVisibility(using: metrics)
                    }
                    .onAppear {
                        resetControlsVisibility()
                        scrollToPendingTarget(using: scrollProxy)
                    }
                    .onChange(of: rowIDs) { _, _ in
                        scrollToPendingTarget(using: scrollProxy)
                    }
                    .onChange(of: pendingScrollTargetID) { _, _ in
                        scrollToPendingTarget(using: scrollProxy)
                    }
                }
            }
        }
        .background(colorStrategy.appBackground(for: tagScope.themeRole, theme: theme))
        .foregroundStyle(colorStrategy.primaryText(for: .neutral, theme: theme))
        .onDisappear {
            resetControlsVisibility()
        }
        .overlay(alignment: .top) {
            topFadeOverlay
        }
        .environment(\.entityListColorStrategy, colorStrategy)
    }

    private var topFadeOverlay: some View {
        let backgroundColor = colorStrategy.appBackground(for: tagScope.themeRole, theme: theme)
        let fadeHeight: CGFloat

        if controlsAreVisible {
            fadeHeight = Self.topFadeHiddenControlsHeight + Self.topFadeVisibleControlsExtension
        } else {
            fadeHeight = Self.topFadeHiddenControlsHeight
        }

        return LinearGradient(
            stops: topFadeStops(color: backgroundColor),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: fadeHeight)
        // .overlay(alignment: .bottom) {
        //     Rectangle()
        //         .fill(.red)
        //         .frame(height: 1)
        // }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        // Behaviour: the fade stays anchored to the top while only its lower
        // edge tracks the controls, so list content never peeks above it.
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: controlsAreVisible)
    }

    private func topFadeStops(color: Color, samples: Int = 10) -> [Gradient.Stop] {
        (0...samples).map { index in
            let location = Double(index) / Double(samples)
            let easedLocation = softenedEaseInOutCubic(location)
            let opacity = Self.topFadeMaximumOpacity * (1 - easedLocation)

            return .init(color: color.opacity(opacity), location: location)
        }
    }

    private func softenedEaseInOutCubic(_ value: Double) -> Double {
        let cubic = easeInOutCubic(value)

        return value + (cubic - value) * Self.topFadeCurveStrength
    }

    private func easeInOutCubic(_ value: Double) -> Double {
        if value < 0.5 {
            return 4 * value * value * value
        }

        return 1 - pow(-2 * value + 2, 3) / 2
    }

    @ViewBuilder
    private var listRows: some View {
        if visibleItemCount == 0 {
            filteredEmptyStateRow
        } else {
            rowContent
            bottomPaddingRow
        }
    }

    private var filteredEmptyStateRow: some View {
        ContentUnavailableView {
            Label(filteredEmptyTitle, systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(filteredEmptyDescription)
        } actions: {
            if preferences.hasActiveFilters {
                Button("Clear Filters") {
                    onClearFilters()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var bottomPaddingRow: some View {
        Color.clear
            .frame(height: Self.bottomContentPadding)
            // Behaviour: the user should be able to scroll the final row
            // completely above the floating add button so the row never feels
            // clipped or harder to tap near the bottom edge.
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func scrollToPendingTarget(using scrollProxy: ScrollViewProxy) {
        guard let pendingScrollTargetID else { return }
        guard rowIDs.contains(pendingScrollTargetID) else { return }

        DispatchQueue.main.async {
            withAnimation {
                scrollProxy.scrollTo(pendingScrollTargetID, anchor: .center)
            }
            self.pendingScrollTargetID = nil
            self.onPendingScrollCompleted?(pendingScrollTargetID)
        }
    }

    private func resetControlsVisibility() {
        controlsVisibilityTracker.reset()
        if !controlsAreVisible {
            controlsAreVisible = true
        }
        onControlsVisibilityChange(true)
    }

    private func updateControlsVisibility(using metrics: EntityListScrollMetrics) {
        let isVisible = controlsVisibilityTracker.update(
            contentOffsetY: metrics.contentOffsetY,
            contentTopInset: metrics.contentTopInset,
            contentBottomLimitY: metrics.contentBottomLimitY,
            timestamp: Date().timeIntervalSinceReferenceDate
        )
        guard controlsAreVisible != isVisible else { return }

        controlsAreVisible = isVisible
        onControlsVisibilityChange(isVisible)
    }

}

private struct EntityListScrollMetrics: Equatable {
    let contentOffsetY: CGFloat
    let contentTopInset: CGFloat
    let contentBottomLimitY: CGFloat
}

@MainActor
private final class EntityListControlsVisibilityTracker {
    private var state = EntityListControlsVisibilityState()

    func reset(isVisible: Bool = true) {
        state.reset(isVisible: isVisible)
    }

    func update(
        contentOffsetY: CGFloat,
        contentTopInset: CGFloat,
        contentBottomLimitY: CGFloat,
        timestamp: TimeInterval
    ) -> Bool {
        state.update(
            contentOffsetY: contentOffsetY,
            contentTopInset: contentTopInset,
            contentBottomLimitY: contentBottomLimitY,
            timestamp: timestamp
        )
    }
}
