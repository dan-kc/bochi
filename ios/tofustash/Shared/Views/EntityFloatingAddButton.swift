import SwiftUI

struct EntityFloatingGlassButton<Label: View>: View {
    let accessibilityIdentifier: String
    let action: () -> Void
    let label: Label

    init(
        accessibilityIdentifier: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(
                    width: EntityFloatingActionButtons.buttonSize,
                    height: EntityFloatingActionButtons.buttonSize
                )
        }
        .tofuGlassButton(borderShape: .circle)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

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
        EntityFloatingGlassButton(accessibilityIdentifier: "entity.search", action: onSearch) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .matchedGeometryEffect(id: "entity.search.icon", in: namespace)
        }
        .matchedGeometryEffect(id: "entity.search.container", in: namespace)
    }

    private var addButton: some View {
        EntityFloatingGlassButton(accessibilityIdentifier: "entity.add", action: onAdd) {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }
}

struct EntityListFloatingActionOverlay: View {
    let showsSearchButton: Bool
    let namespace: Namespace.ID
    @Binding var searchState: EntityListSearchState
    let onAdd: () -> Void

    var body: some View {
        Group {
            if !searchState.isPresented {
                if showsSearchButton {
                    EntityFloatingActionButtons(
                        namespace: namespace,
                        onSearch: {
                            EntityListSearchChrome.present(&searchState)
                        },
                        onAdd: onAdd
                    )
                } else {
                    EntityFloatingAddButton(action: onAdd)
                }
            }
        }
    }
}

// Backward-compatible single add button wrapper for any screens that still only
// need the primary create affordance.
struct EntityFloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        EntityFloatingGlassButton(accessibilityIdentifier: "entity.add", action: action) {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
