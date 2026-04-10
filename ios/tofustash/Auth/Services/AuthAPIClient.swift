import Foundation

// protocol = like a TS interface or Rust trait. Defines a contract that conforming types must implement.
// Sendable = marker protocol (like Rust's Send). Promises this type is safe to pass across concurrency boundaries.
protocol AuthAPIClient: Sendable {
    // async throws = like a TS async function that can throw OR a Rust async fn returning Result.
    // Swift's async/await is similar to JS but built into the language with structured concurrency (closer to Rust's tokio).
    func anonymousAuth(deviceId: String) async throws -> AuthTokens
    func register(email: String, password: String) async throws -> AuthTokens
    func login(email: String, password: String) async throws -> AuthTokens
    func claimAccount(email: String, password: String, accessToken: String) async throws -> AuthTokens
    func refreshTokens(refreshToken: String) async throws -> AuthTokens
    func logout(refreshToken: String) async throws
    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws
    func changeEmail(newEmail: String, password: String, accessToken: String) async throws
}

// struct conforming to protocol = like a class implementing a TS interface, or a Rust struct with an impl for a trait.
struct LiveAuthAPIClient: AuthAPIClient {
    let baseURL: URL
    // private = like TS private. Only accessible within this struct (Swift has no "protected").
    private let session: URLSession
    private let decoder: JSONDecoder

    // init = constructor. `.shared` is a singleton (like a global instance).
    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    // <T: Decodable> = generic with constraint. Like TS `<T extends Decodable>` or Rust `<T: Decodable>`.
    // Decodable = protocol for JSON deserialization (like serde::Deserialize in Rust).
    // Encodable? = Optional<Encodable>. The ? after any type makes it optional.
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "POST",
        body: Encodable? = nil,
        accessToken: String? = nil
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // `if let accessToken` = optional binding shorthand. Unwraps the optional into a non-optional
        // variable of the same name, only entering the block if it's not nil. Like Rust's `if let Some(x) = x`.
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            // try = propagates errors up (like Rust's ?). Must use try before any throwing call.
            request.httpBody = try JSONEncoder().encode(body)
        }

        // Tuple destructuring, like JS `const [data, response] = ...` or Rust `let (data, response) = ...`
        let (data, response) = try await session.data(for: request)

        // as? = conditional downcast (returns nil if it fails). URLResponse is a supertype; HTTPURLResponse is a subtype.
        guard let httpResponse = response as? HTTPURLResponse else {
            // throw = like JS throw or Rust panic, but caught by try/catch (not actually a panic — more like Rust's ? + Error).
            throw ApiError(errors: nil, message: "Invalid response", statusCode: nil)
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            // try? = swallow the error and return nil on failure (like Rust's .ok())
            let errorResponse = try? decoder.decode(ApiErrorResponse.self, from: data)
            throw ApiError(
                errors: errorResponse?.errors,
                message: errorResponse?.message,
                statusCode: httpResponse.statusCode
            )
        }

        // The return type T is inferred from the call site. Swift's type inference picks T based on what the caller expects.
        return try decoder.decode(T.self, from: data)
    }

    // Implicit return: single-expression function bodies don't need `return` (like Rust closures).
    func anonymousAuth(deviceId: String) async throws -> AuthTokens {
        try await request(endpoint: "/auth/anonymous", body: ["deviceId": deviceId])
    }

    func register(email: String, password: String) async throws -> AuthTokens {
        try await request(endpoint: "/auth/register", body: ["email": email, "password": password])
    }

    func login(email: String, password: String) async throws -> AuthTokens {
        try await request(endpoint: "/auth/login", body: ["email": email, "password": password])
    }

    func claimAccount(email: String, password: String, accessToken: String) async throws -> AuthTokens {
        try await request(
            endpoint: "/auth/claim",
            body: ["email": email, "password": password],
            accessToken: accessToken
        )
    }

    func refreshTokens(refreshToken: String) async throws -> AuthTokens {
        try await request(endpoint: "/auth/refresh-tokens", body: ["refreshToken": refreshToken])
    }

    func logout(refreshToken: String) async throws {
        // `let _: SuccessResponse` = assigns to discard, but the explicit type annotation tells the generic
        // request<T> what T is. Without it, Swift can't infer T since the return value isn't used.
        let _: SuccessResponse = try await request(
            endpoint: "/auth/logout",
            body: ["refreshToken": refreshToken]
        )
    }

    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws {
        let _: SuccessResponse = try await request(
            endpoint: "/auth/change-password",
            body: ["currentPassword": currentPassword, "newPassword": newPassword],
            accessToken: accessToken
        )
    }

    func changeEmail(newEmail: String, password: String, accessToken: String) async throws {
        let _: SuccessResponse = try await request(
            endpoint: "/auth/change-email",
            body: ["newEmail": newEmail, "password": password],
            accessToken: accessToken
        )
    }
}

// private at file scope = only visible within this file (like Go's unexported/lowercase convention).
// Decodable = can be deserialized from JSON (like serde::Deserialize in Rust or a Zod schema in TS).
private struct SuccessResponse: Decodable {
    let success: Bool
}
