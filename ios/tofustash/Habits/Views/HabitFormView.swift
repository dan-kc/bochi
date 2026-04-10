import SwiftUI

// The form sheet for creating a new habit. Presented modally (slides up from
// bottom) when the user taps "+". In React terms, this is like a modal component
// that receives an `onClose` callback — but in SwiftUI, dismissal is handled
// via the `dismiss` environment value instead of a prop.
struct HabitFormView: View {
    // @Environment(\.dismiss) is like useContext for a built-in "close this modal" action.
    // Calling `dismiss()` pops a navigation view or dismisses a sheet — like calling
    // `onClose()` in a React modal, but provided by the framework automatically.
    @Environment(\.dismiss) private var dismiss

    // @Environment(HabitStore.self) injects the HabitStore from the environment —
    // exactly like `const habitStore = useContext(HabitStoreContext)` in React.
    // The store was provided by `.environment(habitStore)` in tofustashApp.swift.
    @Environment(HabitStore.self) private var habitStore

    // @State is like useState — local state owned by this view. When these change,
    // SwiftUI re-renders the view automatically (no need to call a setter function,
    // you just assign directly: `name = "new value"`).
    @State private var name = ""
    @State private var description = ""
    @State private var frequencyText = ""

    // Computed property — recalculated on every render, like a derived value
    // you'd compute inside a React component body (before the return).
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 100
    }

    var body: some View {
        // NavigationStack inside the sheet gives us a toolbar (nav bar) with
        // Cancel/Add buttons. Without it, there's no place to put toolbar items.
        // Like wrapping modal content in a <Header> component in React.
        NavigationStack {
            // Form is a system-styled container that groups inputs into sections.
            // It automatically applies iOS form styling (grouped table view).
            // Like a <form> in HTML, but purely visual — no submit event.
            Form {
                // Section groups related fields with a visual separator.
                // Like a <fieldset> in HTML.
                Section {
                    // TextField is like <input type="text"> in React.
                    // `text: $name` uses a binding ($) — a two-way connection
                    // between the TextField and the @State variable. It's like
                    // value={name} onChange={e => setName(e.target.value)} combined
                    // into a single `$` prefix. SwiftUI handles the wiring.
                    TextField("Name", text: $name)

                    // `axis: .vertical` makes this TextField expand vertically
                    // for multiline input — like <textarea> in HTML.
                    // `.lineLimit(3...6)` sets min 3, max 6 visible lines.
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    // This TextField is for numeric input but uses a String binding.
                    // We parse the string to Double ourselves so we can handle empty
                    // input (nil frequency) gracefully — SwiftUI's numeric TextField
                    // doesn't distinguish between "empty" and "0".
                    TextField("Times per day (e.g. 1.0)", text: $frequencyText)
                        // .decimalPad shows a numeric keyboard with a decimal point.
                        // Like inputMode="decimal" in HTML.
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New Habit")
            // .inline makes the title small and centered in the nav bar,
            // rather than the large scrolling title. Better for modal sheets.
            .navigationBarTitleDisplayMode(.inline)
            // .toolbar adds buttons to the navigation bar — like putting buttons
            // in a React modal's header/footer.
            .toolbar {
                // .cancellationAction places the button on the leading (left) side
                // and styles it as a cancel action.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                // .confirmationAction places the button on the trailing (right) side
                // and styles it as a primary action (bold text).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addHabit()
                    }
                    // .disabled() is like the `disabled` prop on a React button.
                    .disabled(!isValid)
                }
            }
        }
    }

    private func addHabit() {
        // Parse the frequency string to a Double. `Double(string)` returns nil
        // if the string isn't a valid number — like parseFloat() returning NaN,
        // but nil instead of NaN. Empty string → nil (no frequency set).
        let frequency: Double? = frequencyText.isEmpty ? nil : Double(frequencyText)

        habitStore.addHabit(
            name: name,
            description: description,
            frequency: frequency
        )

        dismiss()
    }
}

#Preview {
    HabitFormView()
        .environment(HabitStore())
}
