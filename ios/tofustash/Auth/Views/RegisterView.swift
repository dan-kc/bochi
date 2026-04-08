import SwiftUI

struct RegisterView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
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

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Register") {
                    Task { await performRegister() }
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty)
            }
        }
        .navigationTitle("Register")
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func performRegister() async {
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        let validationErrors = validateAuthInput(email: email, password: password)
        if !validationErrors.isEmpty {
            errorMessage = validationErrors.map(\.message).joined(separator: "\n")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await authManager.register(email: email, password: password)
            dismiss()
        } catch {
            if let apiError = error as? ApiError {
                errorMessage = apiError.displayMessage
            } else {
                errorMessage = "Registration failed"
            }
        }

        isLoading = false
    }
}
