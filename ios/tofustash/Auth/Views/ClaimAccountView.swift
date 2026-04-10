import SwiftUI

// Same patterns as RegisterView — see that file for detailed explanations.
struct ClaimAccountView: View {
    @Environment(AuthManager.self) private var authManager // useContext(AuthManager)
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showLogin = false

    var body: some View {
        Form {
            Section {
                Text("Your existing habits will be kept and synced to your new account.")
            }

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
                Button("Create Account") {
                    Task { await performClaim() }
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty || confirmPassword.isEmpty)
            }

            Section {
                Button("Already have an account? Log in") {
                    email = ""
                    password = ""
                    confirmPassword = ""
                    showLogin = true
                }
            }
        }
        .navigationTitle("Create Account")
        .navigationDestination(isPresented: $showLogin) {
            LoginView()
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        // .onAppear = React's useEffect(() => { ... }, []) — runs once when the view appears.
        // Used here as a guard to dismiss if the user is already logged in (not anonymous).
        .onAppear {
            if !authManager.isAnonymous {
                dismiss()
            }
        }
    }

    private func performClaim() async {
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
            try await authManager.claimAccount(email: email, password: password)
            dismiss()
        } catch {
            if let apiError = error as? ApiError {
                errorMessage = apiError.displayMessage
            } else {
                errorMessage = "Failed to create account"
            }
        }

        isLoading = false
    }
}
