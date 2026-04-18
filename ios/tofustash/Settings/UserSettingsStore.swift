import Foundation

@Observable
@MainActor
final class UserSettingsStore {
    private struct PersistedState: Codable {
        var difficultyByOwner: [String: Double] = [:]
    }

    private let storageURL: URL
    private(set) var currentOwnerID: String
    private var difficultyByOwner: [String: Double]

    private(set) var generalDifficulty: Double = 5.0

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "user-settings")
        self.currentOwnerID = initialOwnerID
        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.difficultyByOwner = persisted.difficultyByOwner
        self.generalDifficulty = persisted.difficultyByOwner[initialOwnerID] ?? 5.0
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        generalDifficulty = difficultyByOwner[ownerID] ?? 5.0
    }

    func migrateSettings(from sourceOwnerID: String, to destinationOwnerID: String) -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }
        let sourceDifficulty = difficultyByOwner[sourceOwnerID]
        guard let sourceDifficulty else { return false }

        difficultyByOwner[destinationOwnerID] = sourceDifficulty
        difficultyByOwner[sourceOwnerID] = nil
        persist()
        generalDifficulty = difficultyByOwner[currentOwnerID] ?? 5.0
        return true
    }

    func setGeneralDifficulty(_ value: Double, shouldNotifySync: Bool = true) {
        guard value > 0, value < 1000 else { return }
        generalDifficulty = value
        difficultyByOwner[currentOwnerID] = value
        persist()

        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .generalDifficulty, recordIDs: []))
        }
    }

    private func persist() {
        JSONFileStore.save(PersistedState(difficultyByOwner: difficultyByOwner), to: storageURL)
    }
}
