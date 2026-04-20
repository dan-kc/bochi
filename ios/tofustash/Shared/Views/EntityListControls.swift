import SwiftUI

// Reusable control strip for both list screens. The list itself only shows the
// current sort and tag state, then opens sheets when the user wants to change
// either of those decisions.
struct EntityListControls: View {
    let preferences: EntityListPreferences
    let availableTags: [Tag]
    let tagScope: EntityListTagScope
    let isEnabled: Bool
    let onSelectSort: (EntityListSortOption) -> Void

    @State private var isShowingSortSheet = false
    @State private var isShowingTagsSheet = false

    private var selectedTags: [Tag] {
        let tagsByID = Dictionary(uniqueKeysWithValues: availableTags.map { ($0.id, $0) })
        return preferences.selectedTagIDs.compactMap { tagsByID[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isShowingSortSheet = true
            } label: {
                sortRow
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 42)

            Button {
                isShowingTagsSheet = true
            } label: {
                tagsRow
            }
            .buttonStyle(.plain)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.04), radius: 12, y: 2)
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
        .sheet(isPresented: $isShowingTagsSheet) {
            TagsView(selectionMode: .listFilter(tagScope))
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

    private var sortRow: some View {
        controlRow(
            title: "Sort",
            systemImage: "arrow.up.arrow.down.circle"
        ) {
            Text(preferences.sort.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tagsRow: some View {
        controlRow(
            title: "Tags",
            systemImage: preferences.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "tag.circle"
        ) {
            if selectedTags.isEmpty {
                Text("All tags")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // User behaviour: selected tags should read like active chips at a
                // glance, not like serialized filter text the user has to parse.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedTags) { tag in
                            Text(tag.name)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color(hex: tag.colorHex).opacity(0.14))
                                .foregroundStyle(Color(hex: tag.colorHex))
                                .overlay {
                                    Capsule()
                                        .stroke(Color(hex: tag.colorHex).opacity(0.28), lineWidth: 1)
                                }
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.trailing, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func controlRow<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 26, height: 26)

                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
