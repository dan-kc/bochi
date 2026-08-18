import SwiftUI

// Sync flow: observes dirty-record events and debounces them into manual syncs
// for the currently signed-in owner.
@MainActor
protocol SyncMutationSyncing: AnyObject {
    func syncNow() async
}

extension SyncManager: SyncMutationSyncing { }

struct SyncMutationLifecycleTrigger: Equatable {
    let ownerID: String?
    let revision: Int
}

@MainActor
enum SyncMutationLifecycleCoordinator {
    static func trigger(
        after mutation: SyncMutation,
        activeOwnerID: String?,
        currentTrigger: SyncMutationLifecycleTrigger
    ) -> SyncMutationLifecycleTrigger {
        guard let activeOwnerID, mutation.ownerID == activeOwnerID else {
            return currentTrigger
        }

        return SyncMutationLifecycleTrigger(
            ownerID: activeOwnerID,
            revision: currentTrigger.revision + 1
        )
    }

    static func runDebouncedSync(
        syncManager: SyncMutationSyncing,
        debounceDuration: Duration
    ) async {
        do {
            try await Task.sleep(for: debounceDuration)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        await syncManager.syncNow()
    }
}

private struct SyncMutationLifecycleModifier: ViewModifier {
    let ownerID: String?
    let syncManager: SyncMutationSyncing
    let debounceDuration: Duration

    @State private var latestMutationTrigger = SyncMutationLifecycleTrigger(ownerID: nil, revision: 0)

    func body(content: Content) -> some View {
        let debounceTrigger =
            latestMutationTrigger.ownerID == ownerID
                ? latestMutationTrigger
                : SyncMutationLifecycleTrigger(ownerID: ownerID, revision: 0)

        content
            .task(id: ownerID) {
                latestMutationTrigger = SyncMutationLifecycleTrigger(ownerID: ownerID, revision: 0)
                guard ownerID != nil else { return }

                for await mutation in SyncMutationCenter.mutations() {
                    latestMutationTrigger = SyncMutationLifecycleCoordinator.trigger(
                        after: mutation,
                        activeOwnerID: ownerID,
                        currentTrigger: latestMutationTrigger
                    )
                }
            }
            .task(id: debounceTrigger) {
                guard debounceTrigger.revision > 0 else { return }
                await SyncMutationLifecycleCoordinator.runDebouncedSync(
                    syncManager: syncManager,
                    debounceDuration: debounceDuration
                )
            }
    }
}

extension View {
    func syncMutationLifecycle(
        ownerID: String?,
        syncManager: SyncMutationSyncing,
        debounceDuration: Duration = .seconds(6)
    ) -> some View {
        modifier(
            SyncMutationLifecycleModifier(
                ownerID: ownerID,
                syncManager: syncManager,
                debounceDuration: debounceDuration
            )
        )
    }
}
