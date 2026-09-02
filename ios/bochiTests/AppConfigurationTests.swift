import Foundation
import Testing
@testable import bochi

struct AppConfigurationTests {

    // Behaviour: the normal Bochi scheme uses the Debug project settings so a
    // device build talks to the backend through the Mac's Tailscale address.
    @Test func debugProjectSettingsBuildLocalAPIURL() throws {
        let url = AppConfiguration.makeAPIBaseURL(
            infoDictionary: [
                "BOCHI_API_SCHEME": "http",
                "BOCHI_API_HOST": "dev-mac.local",
                "BOCHI_API_PORT": "8501"
            ]
        )
        let expectedURL = try #require(URL(string: "http://dev-mac.local:8501"))

        #expect(url == expectedURL)
    }

    // Behaviour: the release scheme uses Release project settings so a release
    // build talks to the public backend without carrying the development port.
    @Test func releaseProjectSettingsBuildLiveAPIURL() throws {
        let url = AppConfiguration.makeAPIBaseURL(
            infoDictionary: [
                "BOCHI_API_SCHEME": "https",
                "BOCHI_API_HOST": "bochi.app"
            ]
        )
        let expectedURL = try #require(URL(string: "https://bochi.app"))

        #expect(url == expectedURL)
    }

    // Behaviour: App Review and users should always land on public legal pages
    // from the purchase flow, even when a Debug build points API traffic locally.
    @Test func legalLinksUsePublicDestinations() throws {
        #expect(AppConfiguration.privacyPolicyURL == URL(string: "https://bochi.app/privacy-policy"))
        #expect(AppConfiguration.termsOfUseURL == URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))
    }

    // Behaviour: development-only settings cannot override the generated Release
    // host if they accidentally leak into the app's Info.plist.
    @Test func localProjectSettingDoesNotOverrideGeneratedAPIHost() throws {
        let url = AppConfiguration.makeAPIBaseURL(
            infoDictionary: [
                "BOCHI_API_SCHEME": "https",
                "BOCHI_API_HOST": "bochi.app",
                "BOCHI_API_PORT": "",
                "BOCHI_DEV_MAC_TAILSCALE_IP": "dev-mac.local"
            ]
        )
        let expectedURL = try #require(URL(string: "https://bochi.app"))

        #expect(url == expectedURL)
    }

    // Behaviour: device Debug builds reach a private Mac address, so iOS must have
    // permission copy ready before the first development backend request.
    @Test func debugBuildDeclaresLocalNetworkUsage() throws {
        let description = try #require(Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String)

        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // Behaviour: a Debug device build can make its HTTP API request to the
    // Mac's raw Tailscale IP without weakening transport policy in Release.
    @Test func debugBuildAllowsDevelopmentHTTP() throws {
        let transportSecurity = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        )

        #expect(transportSecurity["NSAllowsArbitraryLoads"] as? Bool == true)
        #expect(transportSecurity["NSAllowsLocalNetworking"] == nil)
    }

    // Behaviour: local builds resolve the seeded account identity from build
    // configuration so the app and database fixture cannot silently drift apart.
    @Test func localBuildResolvesSeededDevelopmentAccount() throws {
        let account = try #require(
            AppConfiguration.makeLocalDevelopmentAccount(
                infoDictionary: [
                    "BOCHI_DEV_AUTH_SUBJECT": "bochi-development-alice",
                    "BOCHI_DEV_AUTH_EMAIL": "alice@example.com"
                ]
            )
        )

        #expect(account.subject == "bochi-development-alice")
        #expect(account.email == "alice@example.com")
    }
}
