import Foundation

struct ApiErrorItem: Codable, Sendable {
    let code: String
    let message: String
}

// Conforming to Error protocol makes this throwable (like implementing std::error::Error in Rust).
struct ApiError: Error, Sendable {
    // `?` suffix = Optional -- like `T | null` in TS or `Option<T>` in Rust.
    let errors: [ApiErrorItem]?
    let message: String?
    let statusCode: Int?

    // The auth UI uses one shared renderer so every screen explains failures consistently.
    // That keeps login/register/claim/settings flows DRY and avoids one screen masking
    // a network failure as "wrong password" while another shows a better message.
    var userFacingMessage: String {
        if let errors, !errors.isEmpty {
            return errors.map(\.message).joined(separator: "\n")
        }

        if let message, !message.isEmpty {
            return message
        }

        return fallbackMessage
    }

    // Behaviour: when the app cannot even talk to the backend, the user should hear that
    // the request never reached the server, not that their credentials were rejected.
    static func networkFailure(_ error: Error) -> ApiError {
        let urlError = error as? URLError

        return ApiError(
            errors: nil,
            message: messageForNetworkError(urlError),
            statusCode: nil
        )
    }

    static func genericFailure(message: String) -> ApiError {
        ApiError(errors: nil, message: message, statusCode: nil)
    }

    private var fallbackMessage: String {
        switch statusCode {
        case 400:
            return "The request could not be completed. Check the form and try again."
        case 401:
            return "Your session is no longer valid. Try signing in again."
        case 500:
            return "The server hit an error. Please try again."
        case nil:
            return "Something went wrong. Please try again."
        default:
            return "The request failed. Please try again."
        }
    }

    private static func messageForNetworkError(_ urlError: URLError?) -> String {
        switch urlError?.code {
        case .notConnectedToInternet:
            return "You appear to be offline. Check your connection and try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "We couldn't connect to the server. Please try again."
        case .timedOut:
            return "The server took too long to respond. Please try again."
        case .networkConnectionLost:
            return "The network connection was interrupted. Please try again."
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return "A secure connection to the server could not be established."
        case .cancelled:
            return "The request was cancelled."
        case .none:
            return "The app could not reach the server. Please try again."
        default:
            return "A network error prevented the request from reaching the server."
        }
    }
}

struct ApiErrorResponse: Codable {
    let errors: [ApiErrorItem]?
    let message: String?
}
