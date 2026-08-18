import SwiftUI

struct EntityFormNavigationModifier<MenuContent: View>: ViewModifier {
    let title: String
    let isToolbarVisible: Bool
    let isNewMode: Bool
    let isEditingText: Bool
    let canCommitNewEntity: Bool
    let onCancel: () -> Void
    let onFinishTextEditing: () -> Void
    let onCommit: () -> Void
    let menuContent: () -> MenuContent

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isToolbarVisible {
                    ToolbarItem(placement: .cancellationAction) {
                        cancellationItem
                    }

                    if showsConfirmationButton {
                        ToolbarItem(placement: .confirmationAction) {
                            confirmationButton
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var cancellationItem: some View {
        if isNewMode {
            Button("Cancel", action: onCancel)
        } else {
            Menu {
                menuContent()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var confirmationButton: some View {
        Button("Done") {
            if isEditingText {
                onFinishTextEditing()
                return
            }

            onCommit()
        }
        .disabled(!isEditingText && isNewMode && !canCommitNewEntity)
    }

    private var showsConfirmationButton: Bool {
        isEditingText || !isNewMode
    }
}

struct EntityFormAddActionButton: View {
    @Environment(\.bochiTheme) private var theme
    let entityName: String
    let isEnabled: Bool
    let action: () -> Void
    var disabledAction: (() -> Void)? = nil

    var body: some View {
        BochiActionSurface(
            layout: .expanded(tint: theme.solidFill(for: .neutral)),
            isEnabled: true,
            action: {
                if isEnabled {
                    action()
                } else {
                    disabledAction?()
                }
            }
        ) {
            Text("Add \(entityName)")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityHint(isEnabled ? "" : "Required fields are missing")
    }
}

extension View {
    func entityFormNavigation<MenuContent: View>(
        title: String,
        isToolbarVisible: Bool = true,
        isNewMode: Bool,
        isEditingText: Bool,
        canCommitNewEntity: Bool,
        onCancel: @escaping () -> Void,
        onFinishTextEditing: @escaping () -> Void,
        onCommit: @escaping () -> Void,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) -> some View {
        modifier(EntityFormNavigationModifier(
            title: title,
            isToolbarVisible: isToolbarVisible,
            isNewMode: isNewMode,
            isEditingText: isEditingText,
            canCommitNewEntity: canCommitNewEntity,
            onCancel: onCancel,
            onFinishTextEditing: onFinishTextEditing,
            onCommit: onCommit,
            menuContent: menuContent
        ))
    }
}
