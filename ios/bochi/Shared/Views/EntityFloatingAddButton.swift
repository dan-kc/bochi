import SwiftUI

private struct OmniSearchNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var omniSearchNamespace: Namespace.ID? {
        get { self[OmniSearchNamespaceKey.self] }
        set { self[OmniSearchNamespaceKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func omniSearchMatchedGeometry(
        id: String,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            self
        }
    }
}

struct EntityFloatingGlassButton<Label: View>: View {
    let action: () -> Void
    let label: Label

    init(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
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
        .bochiGlassButton(borderShape: .circle)
    }
}

// Shared floating action cluster so the main entity tabs keep the same affordances:
// add stays primary, while search opens the app-wide omni finder.
struct EntityFloatingActionButtons: View {
    @Environment(\.bochiTheme) private var theme
    let onSearch: () -> Void
    let onAdd: () -> Void
    @Environment(\.omniSearchNamespace) private var namespace

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
        EntityFloatingGlassButton(action: onSearch) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(theme.primaryText())
                .omniSearchMatchedGeometry(id: "entity.search.icon", namespace: namespace, isSource: false)
        }
        .omniSearchMatchedGeometry(id: "entity.search.container", namespace: namespace, isSource: false)
    }

    private var addButton: some View {
        EntityFloatingGlassButton(action: onAdd) {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(theme.primaryText())
                .omniSearchMatchedGeometry(id: "entity.add.icon", namespace: namespace, isSource: false)
        }
        .omniSearchMatchedGeometry(id: "entity.add.container", namespace: namespace, isSource: false)
    }
}

struct EntityListFloatingActionOverlay: View {
    let showsSearchButton: Bool
    let onAdd: () -> Void
    @Environment(OmniSearchStore.self) private var omniSearchStore

    var body: some View {
        Group {
            if !omniSearchStore.isPresented {
                if showsSearchButton {
                    EntityFloatingActionButtons(
                        onSearch: {
                            omniSearchStore.present()
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
    @Environment(\.bochiTheme) private var theme
    let action: () -> Void

    var body: some View {
        EntityFloatingGlassButton(action: action) {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(theme.primaryText())
        }
        .padding()
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
