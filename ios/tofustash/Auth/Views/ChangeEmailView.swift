import SwiftUI

// Same patterns as RegisterView — see that file for detailed explanations.
struct ChangeEmailView: View {
    @Environment(AuthManager.self) private var authManager // useContext(AuthManager)
    @Environment(\.dismiss) private var dismiss

    @State private var newEmail = "" // useState("")
    @State private var confirmEmail = ""
    @State private var password = ""
    @State private var errorMessage: String? // Optional<String> — like string | undefined
    @State private var isLoading = false

    var body: some View {
        Form {
            Section {
                TextField("New Email", text: $newEmail) // $ = two-way binding
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isLoading)

                TextField("Confirm Email", text: $confirmEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isLoading)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .disabled(isLoading)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Change Email") {
                    Task { await performChange() }
                }
                .disabled(isLoading || newEmail.isEmpty || confirmEmail.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Change Email")
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func performChange() async {
        guard newEmail == confirmEmail else {
            errorMessage = "Email addresses do not match"
            return
        }

        let emailErrors = validateEmail(newEmail)
        if !emailErrors.isEmpty {
            errorMessage = emailErrors.map(\.message).joined(separator: "\n")
            return
        }

        let passwordErrors = validatePassword(password)
        if !passwordErrors.isEmpty {
            errorMessage = passwordErrors.map(\.message).joined(separator: "\n")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await authManager.changeEmail(newEmail: newEmail, password: password)
            dismiss()
        } catch {
            if let apiError = error as? ApiError {
                errorMessage = apiError.displayMessage
            } else {
                errorMessage = "Failed to change email"
            }
        }

        isLoading = false
    }
}
