import Foundation

enum AppConfiguration {
    // Behaviour: Xcode injects these generated Info.plist keys from
    // per-configuration build settings, so changing schemes changes backend.
    private enum APISettingKey {
        static let scheme = "BOCHI_API_SCHEME"
        static let host = "BOCHI_API_HOST"
        static let port = "BOCHI_API_PORT"
    }

    private struct APISettings {
        let scheme: String
        let host: String
        let port: Int?
    }

    private static var fallbackAPISettings: APISettings {
        #if BOCHI_RELEASE
        APISettings(scheme: "https", host: "bochi.app", port: nil)
        #else
        APISettings(scheme: "http", host: "localhost", port: 8501)
        #endif
    }

    static let apiBaseURL = makeAPIBaseURL()
    static let publicWebBaseURL = URL(string: "https://bochi.app")!
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicyURL = publicWebBaseURL.appending(path: "privacy-policy")

    // Small factory so previews and the real app both build the API client the same way.
    static func makeAuthAPIClient(session: URLSession = .shared) -> LiveAuthAPIClient {
        LiveAuthAPIClient(baseURL: apiBaseURL, session: session)
    }

    static func makeSyncAPIClient(session: URLSession = .shared) -> LiveSyncAPIClient {
        LiveSyncAPIClient(baseURL: apiBaseURL, session: session)
    }

    static func resolvedAPIHost(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        resolvedAPISetting(APISettingKey.host, infoDictionary: infoDictionary)
            ?? fallbackAPISettings.host
    }

    static func makeAPIBaseURL(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> URL {
        var components = URLComponents()
        components.scheme = resolvedAPISetting(APISettingKey.scheme, infoDictionary: infoDictionary)
            ?? fallbackAPISettings.scheme
        components.host = resolvedAPIHost(infoDictionary: infoDictionary)
        components.port = resolvedAPIPort(infoDictionary: infoDictionary)

        guard let url = components.url else {
            fatalError("AppConfiguration could not build a valid API base URL.")
        }

        return url
    }

    private static func resolvedAPIPort(infoDictionary: [String: Any]) -> Int? {
        guard let rawPort = rawAPISetting(APISettingKey.port, infoDictionary: infoDictionary) else {
            return hasAPISettings(infoDictionary: infoDictionary) ? nil : fallbackAPISettings.port
        }

        guard !rawPort.isEmpty else {
            return hasAPISettings(infoDictionary: infoDictionary) ? nil : fallbackAPISettings.port
        }

        guard let port = Int(rawPort), port > 0, port <= 65_535 else {
            fatalError("BOCHI_API_PORT must be empty or a valid TCP port.")
        }

        return port
    }

    private static func hasAPISettings(infoDictionary: [String: Any]) -> Bool {
        [
            APISettingKey.scheme,
            APISettingKey.host,
            APISettingKey.port
        ].contains { key in
            infoDictionary[key] != nil
        }
    }

    private static func resolvedAPISetting(
        _ key: String,
        infoDictionary: [String: Any]
    ) -> String? {
        guard let value = rawAPISetting(key, infoDictionary: infoDictionary) else {
            return nil
        }

        return value.isEmpty ? nil : value
    }

    private static func rawAPISetting(
        _ key: String,
        infoDictionary: [String: Any]
    ) -> String? {
        return stringValue(infoDictionary[key])?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            string
        case let number as NSNumber:
            number.stringValue
        default:
            nil
        }
    }
}
