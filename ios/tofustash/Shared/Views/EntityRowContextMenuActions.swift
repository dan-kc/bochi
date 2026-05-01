import SwiftUI

enum EntityRowContextMenuActions {
    @ViewBuilder
    static func editHistoryDelete(
        onEdit: @escaping () -> Void,
        onViewHistory: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        Button {
            onEdit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            onViewHistory()
        } label: {
            Label("View History", systemImage: "clock.arrow.circlepath")
        }

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
