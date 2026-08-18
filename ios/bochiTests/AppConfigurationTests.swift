import Foundation
import Testing
@testable import bochi

struct AppConfigurationTests {

    // Behaviour: the normal Bochi scheme uses the Debug project settings so a
    // device build talks to the backend running on the Mac over Wi-Fi.
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

    // Behaviour: the editable local IP setting is only an input to Debug build
    // settings; if it leaks into the bundle, Release should still use the live host.
    @Test func localProjectSettingDoesNotOverrideGeneratedAPIHost() throws {
        let url = AppConfiguration.makeAPIBaseURL(
            infoDictionary: [
                "BOCHI_API_SCHEME": "https",
                "BOCHI_API_HOST": "bochi.app",
                "BOCHI_API_PORT": "",
                "BOCHI_LOCAL_API_HOST": "dev-mac.local"
            ]
        )
        let expectedURL = try #require(URL(string: "https://bochi.app"))

        #expect(url == expectedURL)
    }

    // Behaviour: device Debug builds talk to a Mac on the local network, so iOS
    // must have permission copy ready before the first local backend request.
    @Test func debugBuildDeclaresLocalNetworkUsage() throws {
        #if BOCHI_LOCAL
        let description = try #require(Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String)

        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #endif
    }
}
