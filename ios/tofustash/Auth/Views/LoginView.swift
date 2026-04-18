import SwiftUI

// Same patterns as RegisterView — see that file for detailed explanations.
struct LoginView: View {
    @Environment(AuthManager.self) private var authManager // useContext(AuthManager)
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showRegister = false // drives navigation — like a boolean that triggers a <Navigate> in React Router

    var body: some View {
        Form {
            Section {
                Text("Sign in to sync your data and attach any premium account benefits to this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
        // Programmatic navigation: when $showRegister becomes true, push RegisterView onto the nav stack.
        // Like useNavigate() in React Router, but declarative — driven by state, not imperative calls.
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
                errorMessage = apiError.userFacingMessage
            } else {
                errorMessage = ApiError.networkFailure(error).userFacingMessage
            }
        }

        isLoading = false
    }
}
