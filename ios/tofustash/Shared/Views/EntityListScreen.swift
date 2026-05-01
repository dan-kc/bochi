import SwiftUI

// Shared list shell for tasks, habits, and rewards. Each screen keeps its own
// row content and pricing logic, but the list chrome should behave the same:
// controls at the top, controls locked while scrolled down, and a distinct
// empty state when filters hide everything.
struct EntityListScreen<RowID: Hashable, RowContent: View>: View {
    // SwiftUI `List` does not expose a CSS-like "padding-bottom" on just the
    // scrollable children. The simplest equivalent is to append a final spacer
    // row with a fixed height. Because all three entity tabs use this shared
    // shell, one constant keeps the extra runway consistent across them.
    private static var bottomContentPadding: CGFloat { 96 }

    let hasAnyItems: Bool
    let visibleItemCount: Int
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let filteredEmptyTitle: String
    let filteredEmptyDescription: String
    let preferences: EntityListPreferences
    let tagScope: EntityListTagScope
    let rowIDs: [RowID]
    let onSelectSort: (EntityListSortOption) -> Void
    let onClearFilters: () -> Void
    let onPendingScrollCompleted: ((RowID) -> Void)?
    let rowContent: RowContent

    @State private var isListAtTop = true
    @Binding private var pendingScrollTargetID: RowID?

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
        rowIDs: [RowID],
        pendingScrollTargetID: Binding<RowID?>,
        onSelectSort: @escaping (EntityListSortOption) -> Void,
        onClearFilters: @escaping () -> Void,
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
        self.rowIDs = rowIDs
        self._pendingScrollTargetID = pendingScrollTargetID
        self.onSelectSort = onSelectSort
        self.onClearFilters = onClearFilters
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
                        controlsRow

                        Section {
                            if visibleItemCount == 0 {
                                filteredEmptyStateRow
                            } else {
                                rowContent
                                    // Behaviour: entity rows should line up with the
                                    // control strip and navigation title. We set the insets
                                    // ourselves so the list stays sharp-edged without the
                                    // grouped container clipping the row content.
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    // Behaviour: once the user has items, every entity
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
                    .animation(.default, value: rowIDs)
                    .onAppear {
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
            tagScope: tagScope,
            isEnabled: isListAtTop,
            onSelectSort: onSelectSort
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.top, -4)
        .padding(.bottom, 12)
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
}
