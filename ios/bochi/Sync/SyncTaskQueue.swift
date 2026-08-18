import Foundation

// Sync flow: serializes manual syncs and passive pulls so only the current
// owner/run can finish visible sync state.
@MainActor
final class SyncTaskQueue {
    private var activeSyncTask: Task<Void, Never>?
    private var activeSyncRunID: UUID?
    private var syncQueueTail: Task<Void, Never>?
    private var syncQueueTailID: UUID?

    func startManualSync(
        operation: @escaping @MainActor (UUID) async -> Void
    ) -> Task<Void, Never> {
        if let activeSyncTask {
            return activeSyncTask
        }

        let runID = UUID()
        let previousTask = syncQueueTail
        let task = Task { @MainActor [weak self, previousTask, runID] in
            await previousTask?.value
            guard let self else { return }
            defer {
                self.finishQueuedOperation(runID)
                self.finishActiveSyncRun(runID)
            }
            guard !Task.isCancelled else { return }
            await operation(runID)
        }
        activeSyncRunID = runID
        activeSyncTask = task
        syncQueueTail = task
        syncQueueTailID = runID
        return task
    }

    func startBackgroundPull(
        operation: @escaping @MainActor (UUID) async -> Void
    ) -> Task<Void, Never> {
        if let syncQueueTail {
            return syncQueueTail
        }

        let runID = UUID()
        let task = Task { @MainActor [weak self, runID] in
            guard let self else { return }
            defer { self.finishQueuedOperation(runID) }
            guard !Task.isCancelled else { return }
            await operation(runID)
        }
        syncQueueTail = task
        syncQueueTailID = runID
        return task
    }

    func cancelAll() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        activeSyncRunID = nil
        syncQueueTail?.cancel()
        syncQueueTail = nil
        syncQueueTailID = nil
    }

    func isActiveSyncRun(_ runID: UUID) -> Bool {
        activeSyncRunID == runID
    }

    private func finishQueuedOperation(_ runID: UUID) {
        guard syncQueueTailID == runID else { return }
        syncQueueTail = nil
        syncQueueTailID = nil
    }

    private func finishActiveSyncRun(_ runID: UUID) {
        guard activeSyncRunID == runID else { return }
        activeSyncTask = nil
        activeSyncRunID = nil
    }
}
