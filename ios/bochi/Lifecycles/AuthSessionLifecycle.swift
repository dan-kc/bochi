import SwiftUI

// Sync flow: observes auth state from SwiftUI and tells SyncManager which owner
// should be active for local display and eventual sync.
struct AuthSessionLifecycleTrigger: Equatable {
    let isBootstrapping: Bool
    let userID: String?
}

@MainActor
protocol AuthSessionUpdating: AnyObject {
    func restoreCachedSession(userID: String)
    func updateSession(userID: String?)
}

extension SyncManager: AuthSessionUpdating { }

@MainActor
enum AuthSessionLifecycleCoordinator {
    static func reconcile(
        trigger: AuthSessionLifecycleTrigger,
        syncManager: AuthSessionUpdating
    ) {
        if trigger.isBootstrapping {
            guard let userID = trigger.userID else { return }
            syncManager.restoreCachedSession(userID: userID)
            return
        }

        syncManager.updateSession(userID: trigger.userID)
    }
}

private struct AuthSessionLifecycleModifier: ViewModifier {
    let authManager: AuthManager
    let syncManager: AuthSessionUpdating

    func body(content: Content) -> some View {
        let trigger = AuthSessionLifecycleTrigger(
            isBootstrapping: authManager.isLoading,
            userID: authManager.user?.id
        )

        content
            .task {
                await authManager.bootstrap()
            }
            .task(id: trigger) {
                AuthSessionLifecycleCoordinator.reconcile(
                    trigger: trigger,
                    syncManager: syncManager
                )
            }
    }
}

extension View {
    func authSessionLifecycle(
        authManager: AuthManager,
        syncManager: AuthSessionUpdating
    ) -> some View {
        modifier(
            AuthSessionLifecycleModifier(
                authManager: authManager,
                syncManager: syncManager
            )
        )
    }
}
