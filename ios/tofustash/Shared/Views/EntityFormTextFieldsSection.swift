import SwiftUI

// Shared text-field shell used by both form screens. This is the SwiftUI
// equivalent of extracting a small reusable JSX fragment instead of cloning
// the same name/description markup in two files.
struct EntityFormTextFieldsSection<FieldFocus: Hashable>: View {
    @Binding var name: String
    @Binding var description: String
    let focusedField: FocusState<FieldFocus?>.Binding
    let nameFocus: FieldFocus
    let descriptionFocus: FieldFocus
    var namePlaceholder: String = "Name"
    var descriptionPlaceholder: String = "Description"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(namePlaceholder, text: $name)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .padding(.vertical, 6)
                .focused(focusedField, equals: nameFocus)

            Divider()

            TextField(descriptionPlaceholder, text: $description, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 6)
                .focused(focusedField, equals: descriptionFocus)
        }
    }
}
