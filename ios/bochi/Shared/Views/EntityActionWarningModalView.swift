import SwiftUI

struct EntityActionWarningModalView: View {
    @Environment(\.bochiTheme) private var theme
    let entityName: String
    let actionTitle: String
    let reason: EntityActionGateReason
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Are you sure?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.primaryText())

                Text(reason.message(entityName: entityName, actionName: actionTitle))
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText())
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button(actionTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.solidFill(for: .neutral))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.appBackground())
        .presentationDetents([.height(230)])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.appBackground())
    }
}
