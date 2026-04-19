import Foundation

@MainActor
final class SyncStateStore {
    struct DirtyState: Codable, Equatable {
        var habits: [RecordID] = []
        var trades: [RecordID] = []
        var tags: [RecordID] = []
        var habitTags: [RecordID] = []
        var rewards: [RecordID] = []
        var rewardTags: [RecordID] = []
        var generalDifficulty: Bool = false
    }

    struct UserSyncState: Codable, Equatable {
        var lastSync: Date?
        var lastFullSyncAt: Date?
        var dirty = DirtyState()
    }

    private struct PersistedState: Codable {
        var statesByUserID: [String: UserSyncState] = [:]
    }

    private let storageURL: URL
    private var statesByUserID: [String: UserSyncState]

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "sync-state")
        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.statesByUserID = persisted.statesByUserID
    }

    func state(for userID: String) -> UserSyncState {
        statesByUserID[userID] ?? UserSyncState()
    }

    func markDirty(userID: String, kind: SyncEntityKind, ids: [RecordID]) {
        var current = state(for: userID)

        switch kind {
        case .habits:
            current.dirty.habits = mergeUnique(current.dirty.habits, ids)
        case .trades:
            current.dirty.trades = mergeUnique(current.dirty.trades, ids)
        case .tags:
            current.dirty.tags = mergeUnique(current.dirty.tags, ids)
        case .habitTags:
            current.dirty.habitTags = mergeUnique(current.dirty.habitTags, ids)
        case .rewards:
            current.dirty.rewards = mergeUnique(current.dirty.rewards, ids)
        case .rewardTags:
            current.dirty.rewardTags = mergeUnique(current.dirty.rewardTags, ids)
        case .generalDifficulty:
            current.dirty.generalDifficulty = true
        }

        statesByUserID[userID] = current
        persist()
    }

    func clearAllDirty(userID: String) {
        var current = state(for: userID)
        current.dirty = DirtyState()
        statesByUserID[userID] = current
        persist()
    }

    func setLastSync(userID: String, serverTime: Date) {
        var current = state(for: userID)
        current.lastSync = serverTime
        statesByUserID[userID] = current
        persist()
    }

    func forceFullSyncOnNextRun(userID: String) {
        var current = state(for: userID)
        current.lastSync = nil
        statesByUserID[userID] = current
        persist()
    }

    func shouldPerformFullSync(userID: String, now: Date = Date()) -> Bool {
        let current = state(for: userID)

        guard current.lastSync != nil else {
            return true
        }

        guard let lastFullSyncAt = current.lastFullSyncAt else {
            return true
        }

        return now.timeIntervalSince(lastFullSyncAt) >= 24 * 60 * 60
    }

    func recordFullSync(userID: String, completedAt: Date = Date()) {
        var current = state(for: userID)
        current.lastFullSyncAt = completedAt
        statesByUserID[userID] = current
        persist()
    }

    private func persist() {
        JSONFileStore.save(PersistedState(statesByUserID: statesByUserID), to: storageURL)
    }

    private func mergeUnique(_ existing: [RecordID], _ incoming: [RecordID]) -> [RecordID] {
        var values = Set(existing)
        for id in incoming {
            values.insert(id)
        }
        return Array(values).sorted { $0.rawValue < $1.rawValue }
    }
}
