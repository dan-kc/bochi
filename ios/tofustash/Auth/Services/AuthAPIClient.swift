import Foundation

protocol AuthAPIClient: Sendable {
    func anonymousAuth(deviceId: String) async throws -> AuthTokens
    func register(email: String, password: String) async throws -> AuthTokens
    func login(email: String, password: String) async throws -> AuthTokens
    func claimAccount(email: String, password: String, accessToken: String) async throws -> AuthTokens
    func refreshTokens(refreshToken: String) async throws -> AuthTokens
    func logout(refreshToken: String) async throws
    func changePassword(currentPassword: String, newPassword: String, accessToken: String) async throws
    func changeEmail(newEmail: String, password: String, accessToken: String) async throws
}

struct LiveAuthAPIClient: AuthAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

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

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApiError(errors: nil, message: "Invalid response", statusCode: nil)
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorResponse = try? decoder.decode(ApiErrorResponse.self, from: data)
            throw ApiError(
                errors: errorResponse?.errors,
                message: errorResponse?.message,
                statusCode: httpResponse.statusCode
            )
        }

        return try decoder.decode(T.self, from: data)
    }

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

private struct SuccessResponse: Decodable {
    let success: Bool
}
