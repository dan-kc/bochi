import SwiftUI

// A modal with Name and Description fields, shared between new and change forms.
//
// In React, this would be a controlled component receiving value/onChange props:
//   <NameDescriptionModal name={name} onNameChange={setName} ... />
//
// In SwiftUI, we use @Binding — a two-way reference to state owned by the parent.
// The parent passes $name and $description, and this view reads AND writes them
// directly. No callback needed — changes propagate automatically.
struct NameDescriptionModal: View {
    @Binding var name: String
    @Binding var description: String
    @Environment(\.dismiss) private var dismiss

    // Which field to focus when the modal appears
    let initialFocus: Field

    // Enum for focus targets — used with @FocusState below
    enum Field: Hashable {
        case name, description
    }

    // @FocusState is SwiftUI's way to programmatically control keyboard focus.
    // Like using useRef + ref.current.focus() in React, but declarative —
    // you set the state variable and SwiftUI moves focus automatically.
    // The ? makes it optional: nil = nothing focused.
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        // .focused($focusedField, equals:) binds this field's focus
                        // to when focusedField == .name. Like managing focus via a
                        // ref in React, but reactive.
                        .focused($focusedField, equals: .name)

                    // axis: .vertical makes this a multiline text field (like <textarea>).
                    // Unlike the main form which truncates to 3 lines, this modal
                    // shows the full description.
                    TextField("Description", text: $description, axis: .vertical)
                        .focused($focusedField, equals: .description)
                        .lineLimit(5...15)
                }
            }
            .navigationTitle("Name & Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        // "xmark" is the SF Symbol for an X/close icon
                        Image(systemName: "xmark")
                    }
                }
            }
            // .onAppear is like useEffect(fn, []) — runs once when the view mounts.
            // We set the focus state here to auto-focus the requested field.
            .onAppear {
                // Small delay ensures the view is fully laid out before focusing.
                // Without this, focus sometimes doesn't take effect.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    focusedField = initialFocus
                }
            }
        }
    }
}
