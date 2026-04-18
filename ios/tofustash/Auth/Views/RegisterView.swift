import SwiftUI

// Like a React FC — `struct Foo: View` means this struct conforms to the View protocol (~ implements an interface in TS/Go).
// SwiftUI structs are value types (like Rust structs), not classes. The framework recreates them on re-render.
struct RegisterView: View {
    // @Environment = React's useContext(). Reads AuthManager from the ancestor-provided environment.
    @Environment(AuthManager.self) private var authManager
    // \.dismiss is a built-in environment action — like calling navigate(-1) or a close-modal callback from context.
    @Environment(\.dismiss) private var dismiss

    // @State = React's useState(). SwiftUI re-renders the view when any @State changes, just like setState.
    // `private` is access control (like Go's unexported lowercase fields).
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    // String? = Option<String> in Rust, or `string | undefined` in TS. The ? makes it an Optional.
    @State private var errorMessage: String?
    @State private var isLoading = false

    // `body` is the required property from the View protocol — think of it as the render() method.
    // `some View` = an opaque return type (like Rust's `impl View`). The compiler knows the concrete type, callers don't.
    var body: some View {
        // Form, Section, TextField etc. are SwiftUI components — like JSX elements. No return keyword needed
        // because Swift has implicit returns for single-expression computed properties.
        Form {
            Section {
                // $email is a Binding — a two-way ref to the @State var. Like passing [value, setValue] as a single object.
                // Think: <input value={email} onChange={e => setEmail(e.target.value)} /> but $email bundles both.
                TextField("Email", text: $email)
                    // Chained methods = "view modifiers" — like chaining className, style, props in JSX.
                    // Each modifier wraps the view, returning a new modified view (immutable builder pattern).
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isLoading)

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .disabled(isLoading)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .disabled(isLoading)
            }

            // `if let errorMessage` unwraps the Optional — like Rust's `if let Some(msg) = error_message`.
            // In SwiftUI, conditional views work like {errorMessage && <Section>...} in JSX.
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                // Trailing closure syntax: Button("Register") { ... } is sugar for Button("Register", action: { ... })
                Button("Register") {
                    // Task { } spawns an async context — like wrapping in an immediately-invoked async IIFE in JS.
                    // Needed because SwiftUI closures aren't async by default.
                    Task { await performRegister() }
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty)
            }
        }
        .navigationTitle("Register")
        // .overlay adds a layer on top, like a positioned absolute div over the form.
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    // `async` = same as JS async. `do/catch` = try/catch in JS, but Swift requires `try` before each throwing call.
    private func performRegister() async {
        // `guard ... else { return }` = early return pattern. Like `if (pw !== confirm) { setError(...); return; }` in JS
        // but guard is specifically designed for the early-exit case — the happy path continues unindented.
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        let validationErrors = validateAuthInput(email: email, password: password)
        if !validationErrors.isEmpty {
            // \.message is a key path (~ a function reference like (x) => x.message, or Rust's |x| x.message)
            errorMessage = validationErrors.map(\.message).joined(separator: "\n")
            return
        }

        isLoading = true
        errorMessage = nil

        // `do { try ... } catch { }` — `try` marks each call that can throw (like Rust's ? but not auto-propagating)
        do {
            try await authManager.register(email: email, password: password)
            dismiss()
        } catch {
            // `as?` is a conditional downcast — like a type guard in TS: `if (error instanceof ApiError)`.
            // Returns nil if the cast fails, hence `if let` to unwrap.
            if let apiError = error as? ApiError {
                errorMessage = apiError.userFacingMessage
            } else {
                errorMessage = ApiError.networkFailure(error).userFacingMessage
            }
        }

        isLoading = false
    }
}
