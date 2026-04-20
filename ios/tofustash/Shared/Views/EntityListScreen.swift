import SwiftUI

// Shared list shell for habits and rewards. Both screens keep their own row
// content and pricing logic, but the list chrome should behave the same:
// controls at the top, controls locked while scrolled down, and a distinct
// empty state when filters hide everything.
struct EntityListScreen<RowContent: View>: View {
    // SwiftUI `List` does not expose a CSS-like "padding-bottom" on just the
    // scrollable children. The simplest equivalent is to append a final spacer
    // row with a fixed height. Because both habits and rewards use this shared
    // shell, one constant keeps the extra runway consistent across both tabs.
    private static let bottomContentPadding: CGFloat = 96

    let hasAnyItems: Bool
    let visibleItemCount: Int
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let filteredEmptyTitle: String
    let filteredEmptyDescription: String
    let preferences: EntityListPreferences
    let availableTags: [Tag]
    let difficultyLabel: String
    let frequencyLabel: String
    let onSelectSort: (EntityListSortOption) -> Void
    let onSelectDifficultyFilter: (EntityListOptionalFieldFilter) -> Void
    let onSelectFrequencyFilter: (EntityListOptionalFieldFilter) -> Void
    let onSelectTagMatchMode: (EntityListTagMatchMode) -> Void
    let onToggleTag: (RecordID) -> Void
    let onClearFilters: () -> Void
    let rowContent: RowContent

    @State private var isListAtTop = true

    init(
        hasAnyItems: Bool,
        visibleItemCount: Int,
        emptyTitle: String,
        emptySystemImage: String,
        emptyDescription: String,
        filteredEmptyTitle: String,
        filteredEmptyDescription: String,
        preferences: EntityListPreferences,
        availableTags: [Tag],
        difficultyLabel: String,
        frequencyLabel: String,
        onSelectSort: @escaping (EntityListSortOption) -> Void,
        onSelectDifficultyFilter: @escaping (EntityListOptionalFieldFilter) -> Void,
        onSelectFrequencyFilter: @escaping (EntityListOptionalFieldFilter) -> Void,
        onSelectTagMatchMode: @escaping (EntityListTagMatchMode) -> Void,
        onToggleTag: @escaping (RecordID) -> Void,
        onClearFilters: @escaping () -> Void,
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
        self.availableTags = availableTags
        self.difficultyLabel = difficultyLabel
        self.frequencyLabel = frequencyLabel
        self.onSelectSort = onSelectSort
        self.onSelectDifficultyFilter = onSelectDifficultyFilter
        self.onSelectFrequencyFilter = onSelectFrequencyFilter
        self.onSelectTagMatchMode = onSelectTagMatchMode
        self.onToggleTag = onToggleTag
        self.onClearFilters = onClearFilters
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
                List {
                    controlsRow

                    Section {
                        if visibleItemCount == 0 {
                            filteredEmptyStateRow
                        } else {
                            rowContent
                                // Behaviour: habit/reward content should line up with the
                                // control strip and navigation title. We set the insets
                                // ourselves so the list stays sharp-edged without the
                                // grouped container clipping the row content.
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                // Behaviour: once the user has items, every habit/reward
                                // row should sit directly on the parent surface instead of
                                // getting the default opaque grouped-cell fill.
                                .listRowBackground(Color.clear)

                            bottomPaddingRow
                        }
                    }
                }
                .lockControlsUnlessScrolledToTop(isAtTop: $isListAtTop)
                .listStyle(.plain)
                .listSectionSpacing(0)
                .contentMargins(.top, 0, for: .scrollContent)
                // Behaviour: the scrolling surface itself also stays transparent,
                // otherwise iOS paints a white grouped background behind clear rows.
                .scrollContentBackground(.hidden)
            }
        }
        .onChange(of: visibleItemCount == 0) { _, isEmpty in
            // User behaviour: if filters hide every row, immediately unlock the
            // controls so the user can fix the filter state without needing to
            // scroll a now-empty list back to the top.
            if isEmpty {
                isListAtTop = true
            }
        }
    }

    private var controlsRow: some View {
        EntityListControls(
            preferences: preferences,
            availableTags: availableTags,
            difficultyLabel: difficultyLabel,
            frequencyLabel: frequencyLabel,
            isEnabled: isListAtTop,
            onSelectSort: onSelectSort,
            onSelectDifficultyFilter: onSelectDifficultyFilter,
            onSelectFrequencyFilter: onSelectFrequencyFilter,
            onSelectTagMatchMode: onSelectTagMatchMode,
            onToggleTag: onToggleTag,
            onClearFilters: onClearFilters
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.top, -12)
        .padding(.bottom, -6)
    }

    private var filteredEmptyStateRow: some View {
        ContentUnavailableView {
            Label(filteredEmptyTitle, systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(filteredEmptyDescription)
        } actions: {
            Button("Clear Filters") {
                onClearFilters()
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
            // Behaviour: the user should be able to scroll the final habit or
            // reward completely above the floating add button so the row never
            // feels clipped or harder to tap near the bottom edge.
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
