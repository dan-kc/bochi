import SwiftUI

// View for managing tags on a habit. Shows all available tags with
// checkmarks for those already applied. Also allows creating, editing,
// and deleting tags.
//
// Port of frontend/components/TagSelectionModal.tsx. The React version
// used a BottomSheet with a ScrollView. In SwiftUI, we use a List inside
// a NavigationStack (presented as a .sheet) which gives us free scrolling,
// swipe-to-delete, and native iOS styling.
struct TagsView: View {
    let habitId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(TagStore.self) private var tagStore

    @State private var searchText = ""
    @State private var isCreatingTag = false
    @State private var editingTag: Tag? = nil
    @State private var editName = ""
    @State private var editColor = ""

    // Tags currently applied to this habit
    private var appliedTagIds: Set<String> {
        Set(tagStore.tagsForHabit(habitId: habitId).map(\.id))
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
            .searchable(text: $searchText, prompt: "Search tags...")
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
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

    // A single row in the tag list — checkbox + color dot + name + edit button
    private func tagRow(_ tag: Tag) -> some View {
        let isApplied = appliedTagIds.contains(tag.id)

        return HStack {
            // Toggle tag on/off for this habit
            Button {
                toggleTag(tag)
            } label: {
                HStack(spacing: 12) {
                    // Checkmark indicator
                    Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isApplied ? .blue : .secondary)

                    // Color dot
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 20, height: 20)

                    Text(tag.name)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Edit button — pencil icon like the React version
            Button {
                editingTag = tag
                editName = tag.name
                editColor = tag.colorHex
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        // Swipe to delete — like swipeable row actions in React Native
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                tagStore.deleteTag(id: tag.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
                    TextField("Hex color (#RRGGBB)", text: $editColor)
                        .autocapitalization(.none)

                    // Color preview
                    if editColor.contains(/^#[0-9A-Fa-f]{6}$/) {
                        HStack {
                            Text("Preview")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Circle()
                                .fill(Color(hex: editColor))
                                .frame(width: 30, height: 30)
                        }
                    }

                    // Preset color grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.presetColors, id: \.self) { color in
                            Button {
                                editColor = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if editColor == color {
                                            Circle()
                                                .strokeBorder(.primary, lineWidth: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
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

    // Preset color palette — same colors as the React version
    private static let presetColors = [
        "#ef4444", "#dc2626", "#b91c1c",
        "#f97316", "#ea580c", "#c2410c",
        "#eab308", "#ca8a04", "#a16207",
        "#22c55e", "#16a34a", "#15803d",
        "#14b8a6", "#0d9488", "#0f766e",
        "#3b82f6", "#2563eb", "#1d4ed8",
        "#6366f1", "#4f46e5", "#4338ca",
        "#a855f7", "#9333ea", "#7e22ce",
        "#ec4899", "#db2777", "#be185d",
        "#6b7280", "#4b5563", "#374151",
    ]

    private func toggleTag(_ tag: Tag) {
        if appliedTagIds.contains(tag.id) {
            tagStore.removeTagFromHabit(tagId: tag.id, habitId: habitId)
        } else {
            tagStore.addTagToHabit(tagId: tag.id, habitId: habitId)
        }
    }

    private func createTagFromSearch() {
        let name = searchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isCreatingTag = true
        if let tag = tagStore.addTag(name: name) {
            tagStore.addTagToHabit(tagId: tag.id, habitId: habitId)
            searchText = ""
            // Open edit sheet for the new tag
            editingTag = tag
            editName = tag.name
            editColor = tag.colorHex
        }
        isCreatingTag = false
    }

    private func saveTagEdit(_ tag: Tag) {
        let validColor = editColor.contains(/^#[0-9A-Fa-f]{6}$/) ? editColor : nil
        tagStore.updateTag(id: tag.id, name: editName, colorHex: validColor)
        editingTag = nil
    }
}
