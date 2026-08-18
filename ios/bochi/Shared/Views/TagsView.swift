import SwiftUI

// View for managing tags on a recurringTask. Shows all available tags with
// checkmarks for those already applied. Also allows creating, editing,
// and deleting tags.
struct TagsView: View {
    @Environment(\.bochiTheme) private var theme
    let assignmentTarget: TagAssignmentTarget
    let shouldNotifySync: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(TagStore.self) private var tagStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isCreatingTag = false
    @State private var editingTag: Tag? = nil
    @State private var editName = ""
    @State private var editColor = ""

    // Tags currently applied to the item being edited.
    private var appliedTagIds: Set<RecordID> {
        Set(tagStore.tags(for: assignmentTarget).map(\.id))
    }

    // Filtered tags based on search
    private var filteredTags: [Tag] {
        let active = tagStore.activeTags
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return active
        }
        let query = searchText.lowercased()
        return active.filter { $0.name.lowercased().contains(query) }
    }

    // Whether the search text matches an existing tag name exactly
    private var searchMatchesExact: Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return true }
        return tagStore.activeTags.contains { $0.name.lowercased() == query }
    }

    var body: some View {
        NavigationStack {
            List {
                // Tag list
                ForEach(filteredTags) { tag in
                    tagRow(tag)
                }

                // "Add from search" button — shows when search doesn't match any tag
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && !searchMatchesExact {
                    Button {
                        createTagFromSearch()
                    } label: {
                        Label("Add \"\(searchText.trimmingCharacters(in: .whitespaces))\"", systemImage: "plus.circle")
                    }
                    .disabled(isCreatingTag)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search tags...")
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(theme.appBackground())
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar {
                // Single "Done" button — tag changes are applied immediately
                // (no save/cancel distinction), so only a dismiss is needed.
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            // Edit tag sheet — presented when editingTag is set.
            // .sheet(item:) is like conditional rendering in React:
            //   {editingTag && <EditSheet tag={editingTag} />}
            // But SwiftUI handles the animation and lifecycle automatically.
            .sheet(item: $editingTag) { tag in
                tagEditSheet(tag)
            }
        }
    }

    // A single row in the tag list — checkbox + tag pill + edit button
    private func tagRow(_ tag: Tag) -> some View {
        let isApplied = appliedTagIds.contains(tag.id)

        return HStack {
            // User behaviour: tapping a tag row should immediately toggle the
            // tag assignment on the item being edited.
            Button {
                toggleTag(tag)
            } label: {
                HStack(spacing: 12) {
                    // Checkmark indicator
                    Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isApplied ? theme.solidFill(for: .neutral) : theme.lowContrastText(for: .neutral))

                    tagPill(name: tag.name, colorHex: tag.colorHex)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Edit button — pencil icon like the React version
            Button {
                isSearchPresented = false
                editName = tag.name
                editColor = tag.colorHex
                editingTag = tag
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(theme.secondaryText())
            }
            .buttonStyle(.plain)
        }
        // Swipe to delete — like swipeable row actions in React Native
        .swipeActions(edge: .trailing) {
            Button {
                deleteTagAndSanitizeFilters(tag.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(theme.destructiveText())
        }
    }

    // Sheet for editing a tag's name and color
    private func tagEditSheet(_ tag: Tag) -> some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Tag name", text: $editName)
                }

                Section("Color") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(BochiTheme.tagPickerPalettes.enumerated()), id: \.offset) { index, palette in
                            let color = BochiTheme.tagPickerStoredHex(for: palette)
                            let lightPreview = BochiTheme.tagPickerPreviewColors(for: palette, colorScheme: .light)
                            let darkPreview = BochiTheme.tagPickerPreviewColors(for: palette, colorScheme: .dark)
                            let isSelected = BochiTheme.tagHex(editColor, matches: palette)

                            Button {
                                editColor = color
                            } label: {
                                HStack(spacing: 12) {
                                    tagPickerPreviewPair(
                                        name: colorOptionName,
                                        lightPreview: lightPreview,
                                        darkPreview: darkPreview
                                    )

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(theme.solidFill(for: .neutral))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(colorOptionName) color option")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .navigationTitle("Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(theme.appBackground())
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear {
                editName = tag.name
                editColor = tag.colorHex
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingTag = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTagEdit(tag)
                    }
                    .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var colorOptionName: String {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Tag" : trimmed
    }

    private func tagPickerPreviewPair(
        name: String,
        lightPreview: (backgroundHex: String, foregroundHex: String, borderHex: String),
        darkPreview: (backgroundHex: String, foregroundHex: String, borderHex: String)
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                tagPickerPreviewPill(name: name, colors: lightPreview)
                tagPickerPreviewPill(name: name, colors: darkPreview)
            }

            VStack(alignment: .leading, spacing: 8) {
                tagPickerPreviewPill(name: name, colors: lightPreview)
                tagPickerPreviewPill(name: name, colors: darkPreview)
            }
        }
    }

    private func tagPickerPreviewPill(
        name: String,
        colors: (backgroundHex: String, foregroundHex: String, borderHex: String)
    ) -> some View {
        Text(name)
            .font(.body)
            .fontWeight(.semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(hex: colors.backgroundHex))
            .foregroundStyle(Color(hex: colors.foregroundHex))
            .overlay {
                Capsule()
                    .stroke(Color(hex: colors.borderHex), lineWidth: 1)
            }
            .clipShape(Capsule())
    }

    private func tagPill(name: String, colorHex: String) -> some View {
        Text(name)
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(BochiTheme.tagBackgroundColor(hex: colorHex))
            .foregroundStyle(theme.tagForegroundColor(hex: colorHex))
            .clipShape(Capsule())
    }

    private func toggleTag(_ tag: Tag) {
        if appliedTagIds.contains(tag.id) {
            tagStore.removeTag(tagId: tag.id, from: assignmentTarget, shouldNotifySync: shouldNotifySync)
        } else {
            tagStore.addTag(tagId: tag.id, to: assignmentTarget, shouldNotifySync: shouldNotifySync)
        }
        sanitizeListFilters()
    }

    private func createTagFromSearch() {
        let name = searchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCreatingTag = true
        if let tag = tagStore.addTag(name: name) {
            tagStore.addTag(tagId: tag.id, to: assignmentTarget, shouldNotifySync: shouldNotifySync)
            sanitizeListFilters()
            isSearchPresented = false
            searchText = ""
            // Open edit sheet for the new tag
            editName = tag.name
            editColor = tag.colorHex
            editingTag = tag
        }
        isCreatingTag = false
    }

    private func saveTagEdit(_ tag: Tag) {
        let validColor = editColor.contains(/^#[0-9A-Fa-f]{6}$/)
            ? BochiTheme.normalizedTagPickerStoredHex(for: editColor)
            : nil
        tagStore.updateTag(id: tag.id, name: editName, colorHex: validColor)
        editingTag = nil
    }

    private func deleteTagAndSanitizeFilters(_ tagID: RecordID) {
        tagStore.deleteTag(id: tagID)
        sanitizeListFilters()
    }

    private func sanitizeListFilters() {
        // User behaviour: when a tag is deleted, any saved list filter pointing
        // at that tag should be removed right away so reopening the list never
        // lands on a stale hidden-results state.
        listPreferencesStore.sanitizeSelectedTags(
            validTaskTagIDs: tagStore.activeTagIDs,
            validRecurringTaskTagIDs: tagStore.activeTagIDs,
            validRewardTagIDs: tagStore.activeTagIDs
        )
    }
}
