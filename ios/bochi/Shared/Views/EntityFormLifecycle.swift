import SwiftUI

struct EntityFormLifecycleModifier<ChangeToken: Equatable>: ViewModifier {
    let changeToken: ChangeToken
    let initialize: () -> Void
    let autoSave: () -> Void
    let shouldDiscard: () -> Bool
    let discard: () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                // Behaviour: the form hydrates once when the sheet appears, then
                // later draft changes can safely autosave existing entities.
                initialize()
            }
            .onChange(of: changeToken) { _, _ in
                autoSave()
            }
            .onDisappear {
                // Behaviour: dismissing a new draft with meaningful edits offers
                // recovery, while saved drafts leave no discard snapshot behind.
                guard shouldDiscard() else { return }
                discard()
            }
    }
}

extension View {
    func entityFormLifecycle<ChangeToken: Equatable>(
        changeToken: ChangeToken,
        initialize: @escaping () -> Void,
        autoSave: @escaping () -> Void,
        shouldDiscard: @escaping () -> Bool,
        discard: @escaping () -> Void
    ) -> some View {
        modifier(EntityFormLifecycleModifier(
            changeToken: changeToken,
            initialize: initialize,
            autoSave: autoSave,
            shouldDiscard: shouldDiscard,
            discard: discard
        ))
    }
}
