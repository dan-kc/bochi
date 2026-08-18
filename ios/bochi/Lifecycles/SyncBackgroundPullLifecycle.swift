import SwiftUI

// Sync flow: polls remote changes for the signed-in owner and routes them
// through SyncManager as silent background pulls.
@MainActor
protocol SyncBackgroundPulling: AnyObject {
    func pullRemoteChangesNow(for userID: String) async
}

extension SyncManager: SyncBackgroundPulling { }

@MainActor
enum SyncBackgroundPullLifecycleCoordinator {
    static func runPull(
        syncManager: SyncBackgroundPulling,
        ownerID: String
    ) async {
        await syncManager.pullRemoteChangesNow(for: ownerID)
    }
}

private struct SyncBackgroundPullLifecycleModifier: ViewModifier {
    let ownerID: String?
    let syncManager: SyncBackgroundPulling
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
                await SyncBackgroundPullLifecycleCoordinator.runPull(
                    syncManager: syncManager,
                    ownerID: ownerID
                )
            }
        }
    }
}

extension View {
    func syncBackgroundPullLifecycle(
        ownerID: String?,
        syncManager: SyncBackgroundPulling,
        interval: Duration = .seconds(10)
    ) -> some View {
        modifier(
            SyncBackgroundPullLifecycleModifier(
                ownerID: ownerID,
                syncManager: syncManager,
                interval: interval
            )
        )
    }
}
