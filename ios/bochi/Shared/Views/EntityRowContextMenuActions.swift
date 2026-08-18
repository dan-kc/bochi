import SwiftUI

enum EntityRowContextMenuActions {
    @ViewBuilder
    static func editHistoryDelete(
        theme: BochiTheme,
        onEdit: @escaping () -> Void,
        onDuplicate: (() -> Void)? = nil,
        onTogglePin: (() -> Void)? = nil,
        isPinned: Bool = false,
        onToggleHidden: (() -> Void)? = nil,
        isHidden: Bool = false,
        onViewHistory: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        Button {
            onEdit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        if let onDuplicate {
            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
        }

        if let onTogglePin {
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }

        if let onToggleHidden {
            Button {
                onToggleHidden()
            } label: {
                Label(isHidden ? "Un-hide" : "Hide", systemImage: isHidden ? "eye" : "eye.slash")
            }
        }

        Button {
            onViewHistory()
        } label: {
            Label("View History", systemImage: "clock.arrow.circlepath")
        }

        Button {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
                .foregroundStyle(theme.destructiveText())
        }
    }
}
