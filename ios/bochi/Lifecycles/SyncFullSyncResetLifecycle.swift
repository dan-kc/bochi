import SwiftUI

// Sync flow: periodically asks SyncManager to treat the next run as a full owner
// refresh instead of an incremental cursor pull.
@MainActor
protocol SyncFullSyncResetting: AnyObject {
    func forceFullSyncOnNextRun(for userID: String)
}

extension SyncManager: SyncFullSyncResetting { }

@MainActor
enum SyncFullSyncResetLifecycleCoordinator {
    static func runReset(
        syncManager: SyncFullSyncResetting,
        ownerID: String
    ) {
        syncManager.forceFullSyncOnNextRun(for: ownerID)
    }
}

private struct SyncFullSyncResetLifecycleModifier: ViewModifier {
    let ownerID: String?
    let syncManager: SyncFullSyncResetting
    let interval: Duration

    func body(content: Content) -> some View {
        content.task(id: ownerID) {
            guard let ownerID else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                SyncFullSyncResetLifecycleCoordinator.runReset(
                    syncManager: syncManager,
                    ownerID: ownerID
                )
            }
        }
    }
}

extension View {
    func syncFullSyncResetLifecycle(
        ownerID: String?,
        syncManager: SyncFullSyncResetting,
        interval: Duration = .seconds(60 * 60 * 24)
    ) -> some View {
        modifier(
            SyncFullSyncResetLifecycleModifier(
                ownerID: ownerID,
                syncManager: syncManager,
                interval: interval
            )
        )
    }
}
