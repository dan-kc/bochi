import SwiftUI

// Shared floating action cluster so the main entity tabs keep the same affordances:
// add stays primary, while search can show when the current list is filtered by name.
struct EntityFloatingActionButtons: View {
    let namespace: Namespace.ID
    let onSearch: () -> Void
    let onAdd: () -> Void

    static var buttonSize: CGFloat { 40 }

    var body: some View {
        HStack(spacing: 6) {
            searchButton
            addButton
        }
        .padding()
        // Behaviour: the floating actions belong to the screen, not the search
        // accessory. When the keyboard opens, the keyboard should cover them
        // instead of pushing them upward into the user's way.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var searchButton: some View {
        Button(action: onSearch) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .matchedGeometryEffect(id: "entity.search.icon", in: namespace)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
        }
        .tofuGlassButton(borderShape: .circle)
        .matchedGeometryEffect(id: "entity.search.container", in: namespace)
        .accessibilityIdentifier("entity.search")
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
        }
        .tofuGlassButton(borderShape: .circle)
        .accessibilityIdentifier("entity.add")
    }
}

// Backward-compatible single add button wrapper for any screens that still only
// need the primary create affordance.
struct EntityFloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(width: EntityFloatingActionButtons.buttonSize, height: EntityFloatingActionButtons.buttonSize)
        }
        .tofuGlassButton(borderShape: .circle)
        .accessibilityIdentifier("entity.add")
        .padding()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
