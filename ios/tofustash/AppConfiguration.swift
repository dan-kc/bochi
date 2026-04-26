import Foundation

// Caseless enum used as a namespace — can't be instantiated (like a TS namespace, or a Go package with only exported vars)
enum AppConfiguration {
    // One place to define the backend address keeps the native app DRY.
    // Behaviour: when you run the app on your iPhone during development, it should
    // talk to the server running on this laptop over Wi-Fi instead of the phone's
    // own loopback interface (`localhost` on the phone would point back to the phone).
    private static let defaultDevelopmentHost = "192.168.1.196"
    private static let defaultScheme = "http"
    private static let defaultPort = 8501
    private static let apiHostOverrideEnvironmentKey = "TOFUSTASH_API_HOST"

    // `static let` is like exporting a module-level constant in TS.
    static let apiBaseURL = makeAPIBaseURL()

    // Small factory so previews and the real app both build the API client the same way.
    static func makeAuthAPIClient(session: URLSession = .shared) -> LiveAuthAPIClient {
        LiveAuthAPIClient(baseURL: apiBaseURL, session: session)
    }

    static func makeSyncAPIClient(session: URLSession = .shared) -> LiveSyncAPIClient {
        LiveSyncAPIClient(baseURL: apiBaseURL, session: session)
    }

    static func resolvedAPIHost(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        // `trimmingCharacters` is roughly like JS `.trim()`.
        let override = environment[apiHostOverrideEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Behaviour: when your laptop's LAN IP changes, you can override it in the
        // Xcode scheme without editing source code again.
        if let override, !override.isEmpty {
            return override
        }

        return defaultDevelopmentHost
    }

    static func makeAPIBaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        var components = URLComponents()
        components.scheme = defaultScheme
        components.host = resolvedAPIHost(environment: environment)
        components.port = defaultPort

        // `guard let` is an early-return unwrap, similar to:
        // `const url = maybeUrl; if (!url) throw ...`
        guard let url = components.url else {
            fatalError("AppConfiguration could not build a valid API base URL.")
        }

        return url
    }
}
