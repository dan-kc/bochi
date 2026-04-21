import SwiftUI

// Reusable control strip for both list screens. The list itself only shows the
// current sort and tag state, then opens sheets when the user wants to change
// either of those decisions.
struct EntityListControls: View {
    let preferences: EntityListPreferences
    let tagScope: EntityListTagScope
    let isEnabled: Bool
    let onSelectSort: (EntityListSortOption) -> Void

    @State private var isShowingTagsSheet = false

    var body: some View {
        HStack(spacing: 10) {
            controlButton(
                title: "Filter",
                systemImage: preferences.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                isHighlighted: preferences.hasActiveFilters
            ) {
                isShowingTagsSheet = true
            }

            sortButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Behaviour: while the user is reading farther down the list, freeze the
        // buttons so an accidental tap cannot reorder the content and make them
        // lose their place.
        .allowsHitTesting(isEnabled)
        .animation(.none, value: preferences)
        .transaction { transaction in
            transaction.animation = nil
        }
        .sheet(isPresented: $isShowingTagsSheet) {
            TagsView(selectionMode: .listFilter(tagScope))
        }
    }

    private var sortButton: some View {
        Menu {
            Picker(
                "Sort",
                selection: Binding(
                    get: { preferences.sort },
                    set: onSelectSort
                )
            ) {
                ForEach(EntityListSortOption.allCases) { option in
                    Text("\(option.menuFieldLabel) \(option.directionLabel)")
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(preferences.sort.fieldLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                Text(preferences.sort.directionArrow)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .overlay {
                Capsule()
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func controlButton(
        title: String,
        systemImage: String,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isHighlighted ? .orange : .secondary)

                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isHighlighted ? .orange : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .overlay {
                Capsule()
                    .stroke(isHighlighted ? Color.orange : Color(.separator).opacity(0.35), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
