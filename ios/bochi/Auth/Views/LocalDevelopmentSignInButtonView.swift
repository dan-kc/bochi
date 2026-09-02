#if BOCHI_LOCAL
import SwiftUI

struct LocalDevelopmentSignInButtonView: View {
    @Environment(AuthManager.self) private var authManager

    @Binding var errorMessage: String?
    @Binding var isLoading: Bool

    var body: some View {
        Button {
            Task { await signInAsDevelopmentAccount() }
        } label: {
            Label("Sign in as Alice", systemImage: "person.crop.circle.badge.checkmark")
        }
        .disabled(isLoading)
    }

    private func signInAsDevelopmentAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authManager.signInForLocalDevelopment(
                account: AppConfiguration.localDevelopmentAccount
            )
        } catch {
            if let apiError = error as? ApiError {
                errorMessage = apiError.userFacingMessage
            } else {
                errorMessage = ApiError.networkFailure(error).userFacingMessage
            }
        }
    }
}
#endif
