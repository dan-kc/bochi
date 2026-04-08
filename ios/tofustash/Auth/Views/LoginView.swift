import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showRegister = false

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
                Button("Log In") {
                    Task { await performLogin() }
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)
            }

            Section {
                Button("Create an account") {
                    email = ""
                    password = ""
                    showRegister = true
                }
            }
        }
        .navigationTitle("Log In")
        .navigationDestination(isPresented: $showRegister) {
            RegisterView()
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func performLogin() async {
        let validationErrors = validateAuthInput(email: email, password: password)
        if !validationErrors.isEmpty {
            errorMessage = validationErrors.map(\.message).joined(separator: "\n")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await authManager.login(email: email, password: password)
            dismiss()
        } catch {
            if let apiError = error as? ApiError {
                errorMessage = apiError.displayMessage
            } else {
                errorMessage = "Invalid email or password"
            }
        }

        isLoading = false
    }
}
