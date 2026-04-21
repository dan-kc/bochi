import Foundation

@Observable
@MainActor
final class HabitStore {
    private struct PersistedState: Codable {
        var habitsByOwner: [String: [Habit]] = [:]
    }

    private let storageURL: URL
    private(set) var currentOwnerID: String
    private var habitsByOwner: [String: [Habit]]

    private(set) var habits: [Habit] = []

    var activeHabits: [Habit] {
        habits.filter { $0.deletedAt == nil }
    }

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "habits")
        self.currentOwnerID = initialOwnerID
        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.habitsByOwner = Self.normalizePersistedHabits(persisted.habitsByOwner)
        self.habits = OwnerScopedRecordSupport.recordsForOwner(self.habitsByOwner, ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        habits = OwnerScopedRecordSupport.recordsForOwner(habitsByOwner, ownerID: ownerID)
    }

    func migrateHabits(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        let migratedIDs = OwnerScopedRecordSupport.migrateRecords(
            from: sourceOwnerID,
            to: destinationOwnerID,
            recordsByOwner: &habitsByOwner
        )
        persist()
        refreshCurrentHabits()
        return migratedIDs
    }

    @discardableResult
    func addHabit(
        id: RecordID? = nil,
        name: String,
        description: String = "",
        frequency: Double? = nil,
        difficultyTier: HabitDifficultyTier? = nil,
        durationSeconds: Int? = nil,
        lockoutDurationSeconds: Int? = nil,
        skipConsequence: Int? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> Habit? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }
        let canonicalID = id ?? RecordID()

        let now = Date()
        let habit = Habit(
            id: canonicalID,
            name: trimmedName,
            description: description,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            frequency: frequency,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            lockoutDurationSeconds: lockoutDurationSeconds,
            skipConsequence: skipConsequence
        )

        mutateHabits {
            $0.removeAll { $0.id == habit.id }
            $0.append(habit)
        }

        if shouldNotifySync {
            notifySync(ids: [habit.id])
        }

        return habit
    }

    func deleteHabit(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        let canonicalID = id
        guard let index = habits.firstIndex(where: { $0.id == canonicalID }) else {
            return
        }

        let existing = habits[index]
        let deleted = Habit(
            id: existing.id,
            name: existing.name,
            description: existing.description,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            frequency: existing.frequency,
            difficultyTier: existing.difficultyTier,
            durationSeconds: existing.durationSeconds,
            lockoutDurationSeconds: existing.lockoutDurationSeconds,
            skipConsequence: existing.skipConsequence
        )

        mutateHabits { $0[index] = deleted }

        if shouldNotifySync {
            notifySync(ids: [canonicalID])
        }
    }

    func updateHabit(
        id: RecordID,
        name: String? = nil,
        description: String? = nil,
        frequency: Double?? = nil,
        difficultyTier: HabitDifficultyTier?? = nil,
        durationSeconds: Int?? = nil,
        lockoutDurationSeconds: Int?? = nil,
        skipConsequence: Int?? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        let canonicalID = id
        guard let index = habits.firstIndex(where: { $0.id == canonicalID }) else {
            return
        }

        let existing = habits[index]

        let newName: String
        if let name = name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count <= 100 {
                newName = trimmed
            } else {
                newName = existing.name
            }
        } else {
            newName = existing.name
        }

        let updated = Habit(
            id: existing.id,
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? existing.deletedAt,
            frequency: frequency ?? existing.frequency,
            difficultyTier: difficultyTier ?? existing.difficultyTier,
            durationSeconds: durationSeconds ?? existing.durationSeconds,
            lockoutDurationSeconds: lockoutDurationSeconds ?? existing.lockoutDurationSeconds,
            skipConsequence: skipConsequence ?? existing.skipConsequence
        )

        mutateHabits { $0[index] = updated }

        if shouldNotifySync {
            notifySync(ids: [canonicalID])
        }
    }

    func mergeHabits(_ remoteHabits: [Habit]) {
        guard !remoteHabits.isEmpty else { return }
        mutateHabits {
            $0 = OwnerScopedRecordSupport.mergeRecords(local: $0, remote: remoteHabits)
        }
    }

    func replaceHabits(_ authoritativeHabits: [Habit]) {
        habits = OwnerScopedRecordSupport.sorted(authoritativeHabits)
        habitsByOwner[currentOwnerID] = habits
        persist()
    }

    func getDirtyHabits(ids: Set<RecordID>) -> [Habit] {
        habits.filter { ids.contains($0.id) }
    }

    func purgeDeletedHabits() {
        mutateHabits {
            $0.removeAll { $0.deletedAt != nil }
        }
    }

    func allHabitIDs() -> [RecordID] {
        habits.map(\.id)
    }

    private func mutateHabits(_ mutate: (inout [Habit]) -> Void) {
        habits = OwnerScopedRecordSupport.mutateRecords(
            currentRecords: habits,
            ownerID: currentOwnerID,
            recordsByOwner: &habitsByOwner,
            mutate: mutate
        )
        persist()
    }

    private func refreshCurrentHabits() {
        habits = OwnerScopedRecordSupport.recordsForOwner(habitsByOwner, ownerID: currentOwnerID)
    }

    private func persist() {
        JSONFileStore.save(PersistedState(habitsByOwner: habitsByOwner), to: storageURL)
    }

    private static func normalizePersistedHabits(_ habitsByOwner: [String: [Habit]]) -> [String: [Habit]] {
        OwnerScopedRecordSupport.normalizePersistedRecords(habitsByOwner) { habit in
            Habit(
                id: RecordID(rawValue: habit.id.rawValue),
                name: habit.name,
                description: habit.description,
                createdAt: habit.createdAt,
                updatedAt: habit.updatedAt,
                deletedAt: habit.deletedAt,
                frequency: habit.frequency,
                difficultyTier: habit.difficultyTier,
                durationSeconds: habit.durationSeconds,
                lockoutDurationSeconds: habit.lockoutDurationSeconds,
                skipConsequence: habit.skipConsequence
            )
        }
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .habits, recordIDs: ids))
    }
}
