import SwiftUI

// Shared list shell for habits and rewards. Both screens keep their own row
// content and pricing logic, but the list chrome should behave the same:
// controls at the top, controls locked while scrolled down, and a distinct
// empty state when filters hide everything.
struct EntityListScreen<RowContent: View>: View {
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
                        }
                    }
                }
                .lockControlsUnlessScrolledToTop(isAtTop: $isListAtTop)
                .listStyle(.insetGrouped)
                .listSectionSpacing(0)
                .contentMargins(.top, 0, for: .scrollContent)
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
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
