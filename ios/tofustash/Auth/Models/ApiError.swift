import Foundation

struct ApiErrorItem: Codable, Sendable {
    let code: String
    let message: String
}

struct ApiError: Error, Sendable {
    let errors: [ApiErrorItem]?
    let message: String?
    let statusCode: Int?

    var displayMessage: String {
        if let errors, let first = errors.first {
            return first.message
        }
        return message ?? "An unknown error occurred"
    }
}

struct ApiErrorResponse: Codable {
    let errors: [ApiErrorItem]?
    let message: String?
}
