import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AppleSignInButtonView: View {
    @Environment(AuthManager.self) private var authManager

    @Binding var errorMessage: String?
    @Binding var isLoading: Bool

    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = AppleSignInNonce.random()
            currentNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = AppleSignInNonce.sha256(nonce)
        } onCompletion: { result in
            Task { await handleAuthorization(result) }
        }
        .frame(height: 44)
        .disabled(isLoading)
    }

    private func handleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            await finishSignIn(authorization)
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            errorMessage = ApiError.networkFailure(error).userFacingMessage
        }
    }

    private func finishSignIn(_ authorization: ASAuthorization) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            errorMessage = "Apple did not return a valid sign-in token. Try again."
            return
        }
        let authorizationCode = credential.authorizationCode.flatMap {
            String(data: $0, encoding: .utf8)
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await authManager.signInWithApple(
                identityToken: identityToken,
                email: credential.email,
                nonce: nonce,
                authorizationCode: authorizationCode
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

enum AppleSignInNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard status == errSecSuccess else {
                fatalError("Unable to generate Apple sign-in nonce.")
            }

            randomBytes.forEach { randomByte in
                if remainingLength == 0 {
                    return
                }

                if Int(randomByte) < charset.count {
                    result.append(charset[Int(randomByte)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    static func sha256(_ value: String) -> String {
        let inputData = Data(value.utf8)
        let hashedData = SHA256.hash(data: inputData)

        return hashedData.map { byte in
            String(format: "%02x", byte)
        }
        .joined()
    }
}
