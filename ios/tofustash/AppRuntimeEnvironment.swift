import Foundation

enum AppRuntimeEnvironment {
    private static let environment = ProcessInfo.processInfo.environment

    static var isUITesting: Bool {
        environment["TOFUSTASH_UI_TEST_MODE"] == "1"
    }

    static var storageDirectoryURL: URL? {
        guard let rawPath = environment["TOFUSTASH_STORAGE_DIR"], !rawPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: rawPath, isDirectory: true)
    }
}
