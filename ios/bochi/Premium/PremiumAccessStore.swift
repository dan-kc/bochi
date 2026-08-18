import Foundation

@Observable
@MainActor
final class PremiumAccessStore {
    func hasPremiumAccess(authManager: AuthManager) -> Bool {
        authManager.isPremiumEntitled
    }
}
