import Foundation

enum AppRuntimeEnvironment {
    private static let environment = ProcessInfo.processInfo.environment

    static var storageDirectoryURL: URL? {
        guard let rawPath = environment["BOCHI_STORAGE_DIR"], !rawPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: rawPath, isDirectory: true)
    }
}
