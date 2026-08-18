import SwiftUI

// Sync flow: starts an initial manual sync whenever SyncManager publishes a new
// signed-in owner session.
@MainActor
protocol SyncSessionStarting: AnyObject {
    func syncNow() async
}

extension SyncManager: SyncSessionStarting { }

@MainActor
enum SyncSessionLifecycleCoordinator {
    static func runInitialSync(
        syncManager: SyncSessionStarting,
        session: SyncSession
    ) async {
        guard session.ownerID != nil else { return }
        await syncManager.syncNow()
    }
}

private struct SyncSessionLifecycleModifier: ViewModifier {
    let session: SyncSession
    let syncManager: SyncSessionStarting

    func body(content: Content) -> some View {
        content.task(id: session) {
            await SyncSessionLifecycleCoordinator.runInitialSync(
                syncManager: syncManager,
                session: session
            )
        }
    }
}

extension View {
    func syncSessionLifecycle(
        session: SyncSession,
        syncManager: SyncSessionStarting
    ) -> some View {
        modifier(
            SyncSessionLifecycleModifier(
                session: session,
                syncManager: syncManager
            )
        )
    }
}
