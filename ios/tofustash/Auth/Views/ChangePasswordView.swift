import SwiftUI

struct ChangePasswordView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Form {
            Section {
                SecureField("Current Password", text: $currentPassword)
                    .textContentType(.password)
                    .disabled(isLoading)

                SecureField("New Password", text: $newPassword)
                    .textContentType(.newPassword)
                    .disabled(isLoading)

                SecureField("Confirm New Password", text: $confirmPassword)
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
                Button("Change Password") {
                    Task { await performChange() }
                }
                .disabled(isLoading || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
            }
        }
        .navigationTitle("Change Password")
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func performChange() async {
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        guard currentPassword != newPassword else {
            errorMessage = "New password must be different from current password"
            return
        }

        let passwordErrors = validatePassword(newPassword)
        if !passwordErrors.isEmpty {
            errorMessage = passwordErrors.map(\.message).joined(separator: "\n")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await authManager.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            dismiss()
        } catch {
            if let apiError = error as? ApiError {
                errorMessage = apiError.displayMessage
            } else {
                errorMessage = "Failed to change password"
            }
        }

        isLoading = false
    }
}
