import SwiftUI

// Reusable control strip for both list screens. The controls stay lightweight
// in the list itself, then open bottom sheets when the user wants to configure
// sorting or filtering in more detail.
struct EntityListControls: View {
    let preferences: EntityListPreferences
    let availableTags: [Tag]
    let difficultyLabel: String
    let frequencyLabel: String
    let isEnabled: Bool
    let onSelectSort: (EntityListSortOption) -> Void
    let onSelectDifficultyFilter: (EntityListOptionalFieldFilter) -> Void
    let onSelectFrequencyFilter: (EntityListOptionalFieldFilter) -> Void
    let onSelectTagMatchMode: (EntityListTagMatchMode) -> Void
    let onToggleTag: (RecordID) -> Void
    let onClearFilters: () -> Void

    @State private var isShowingSortSheet = false
    @State private var isShowingFiltersSheet = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                Button {
                    isShowingSortSheet = true
                } label: {
                    controlLabel(title: "Sort", systemImage: "arrow.up.arrow.down.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    isShowingFiltersSheet = true
                } label: {
                    controlLabel(title: filtersButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(.leading, 0)
            .padding(.trailing, 16)
            .padding(.top, 0)
            .padding(.bottom, 0)
        }
        // Behaviour: while the user is reading farther down the list, freeze the
        // buttons so an accidental tap cannot reorder the content and make them
        // lose their place.
        .allowsHitTesting(isEnabled)
        .animation(.none, value: preferences)
        .transaction { transaction in
            transaction.animation = nil
        }
        .sheet(isPresented: $isShowingSortSheet) {
            sortSheet
        }
        .sheet(isPresented: $isShowingFiltersSheet) {
            filtersSheet
        }
    }

    private var sortSheet: some View {
        NavigationStack {
            List {
                Section("Sort") {
                    ForEach(EntityListSortOption.allCases) { option in
                        Button {
                            onSelectSort(option)
                            isShowingSortSheet = false
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if option == preferences.sort {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Sort")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
            .presentationBackground(.thinMaterial)
            .presentationContentInteraction(.scrolls)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingSortSheet = false
                    }
                }
            }
        }
    }

    private var filtersSheet: some View {
        NavigationStack {
            List {
                Section(difficultyLabel) {
                    ForEach(EntityListOptionalFieldFilter.allCases) { filter in
                        Button {
                            onSelectDifficultyFilter(filter)
                        } label: {
                            rowLabel(
                                title: filter.label(fieldName: difficultyLabel),
                                isSelected: filter == preferences.difficultyFilter
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(frequencyLabel) {
                    ForEach(EntityListOptionalFieldFilter.allCases) { filter in
                        Button {
                            onSelectFrequencyFilter(filter)
                        } label: {
                            rowLabel(
                                title: filter.label(fieldName: frequencyLabel),
                                isSelected: filter == preferences.frequencyFilter
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Tag Matching") {
                    ForEach(EntityListTagMatchMode.allCases) { mode in
                        Button {
                            onSelectTagMatchMode(mode)
                        } label: {
                            rowLabel(
                                title: mode.label,
                                isSelected: mode == preferences.tagMatchMode
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Tags") {
                    if availableTags.isEmpty {
                        Text("No tags yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableTags) { tag in
                            Button {
                                onToggleTag(tag.id)
                            } label: {
                                HStack {
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if preferences.selectedTagIDs.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if preferences.hasActiveFilters {
                    Section {
                        Button("Clear Filters", role: .destructive) {
                            onClearFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(.thinMaterial)
            .presentationContentInteraction(.scrolls)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingFiltersSheet = false
                    }
                }
            }
        }
    }

    private var filtersButtonTitle: String {
        preferences.hasActiveFilters ? "Filters On" : "Filters"
    }

    private func rowLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }

    private func controlLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: preferences.hasActiveFilters && title == filtersButtonTitle ? "line.3.horizontal.decrease.circle.fill" : systemImage)
            Text(title)
        }
        .font(.body)
        .fontWeight(.medium)
        .foregroundStyle(.blue)
        .contentShape(Rectangle())
    }
}
