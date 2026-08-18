import SwiftUI

struct EntityFormEditMenu: View {
    @Environment(\.bochiTheme) private var theme
    let entityName: String
    let onDuplicate: () -> Void
    let onToggleHidden: (() -> Void)?
    let isHidden: Bool
    let onHistory: () -> Void
    let onDelete: () -> Void

    init(
        entityName: String,
        onDuplicate: @escaping () -> Void,
        onToggleHidden: (() -> Void)? = nil,
        isHidden: Bool = false,
        onHistory: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.entityName = entityName
        self.onDuplicate = onDuplicate
        self.onToggleHidden = onToggleHidden
        self.isHidden = isHidden
        self.onHistory = onHistory
        self.onDelete = onDelete
    }

    var body: some View {
        Button("Duplicate", action: onDuplicate)

        if let onToggleHidden {
            Button(isHidden ? "Un-hide" : "Hide", action: onToggleHidden)
        }

        Button("History", action: onHistory)

        Button("Delete \(entityName)", action: onDelete)
            .foregroundStyle(theme.destructiveText())
    }
}

extension View {
    func entityDeleteConfirmation<Item>(
        entityName: String,
        isPresented: Binding<Bool>,
        item: Item?,
        onDelete: @escaping (Item) -> Void
    ) -> some View {
        alert("Delete \(entityName)?", isPresented: isPresented) {
            if let item {
                Button("Delete") {
                    onDelete(item)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
