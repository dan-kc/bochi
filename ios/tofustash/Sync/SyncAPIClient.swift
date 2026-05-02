import Foundation

protocol SyncAPIClient: Sendable {
    func pullSync(cursor: String?, accessToken: String) async throws -> SyncResponse
    func pushSync(_ request: SyncPushRequest, accessToken: String) async throws -> SyncResponse
}

struct LiveSyncAPIClient: SyncAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = AppDateCoding.makeDecoder()
    }

    func pullSync(cursor: String?, accessToken: String) async throws -> SyncResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/sync"), resolvingAgainstBaseURL: false)
        if let cursor {
            components?.queryItems = [
                URLQueryItem(name: "cursor", value: cursor)
            ]
        }

        guard let url = components?.url else {
            throw ApiError.genericFailure(message: "The sync request URL could not be built.")
        }

        return try await request(url: url, method: "GET", body: Optional<SyncPushRequest>.none, accessToken: accessToken)
    }

    func pushSync(_ requestBody: SyncPushRequest, accessToken: String) async throws -> SyncResponse {
        let url = baseURL.appendingPathComponent("/api/v1/sync")
        return try await request(url: url, method: "POST", body: requestBody, accessToken: accessToken)
    }

    private func request<T: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        body: Body?,
        accessToken: String
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ApiError.networkFailure(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApiError.genericFailure(message: "The server returned an invalid sync response.")
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let errorResponse = try? decoder.decode(ApiErrorResponse.self, from: data)
            throw ApiError(
                errors: errorResponse?.errors,
                message: errorResponse?.message,
                statusCode: httpResponse.statusCode
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ApiError.genericFailure(message: "The app could not decode the sync response.")
        }
    }
}
