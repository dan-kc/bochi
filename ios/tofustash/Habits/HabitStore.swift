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
        self.habitsByOwner = persisted.habitsByOwner
        self.habits = persisted.habitsByOwner[initialOwnerID] ?? []
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        habits = habitsByOwner[ownerID] ?? []
    }

    func migrateHabits(from sourceOwnerID: String, to destinationOwnerID: String) -> [String] {
        guard sourceOwnerID != destinationOwnerID else { return [] }

        let source = habitsByOwner[sourceOwnerID] ?? []
        let destination = habitsByOwner[destinationOwnerID] ?? []
        let merged = mergeRecords(local: destination, remote: source)
        let migratedIDs = source.map(\.id)

        habitsByOwner[destinationOwnerID] = merged
        habitsByOwner[sourceOwnerID] = []
        persist()
        refreshCurrentHabits()
        return migratedIDs
    }

    @discardableResult
    func addHabit(
        id: String? = nil,
        name: String,
        description: String = "",
        frequency: Double? = nil,
        difficultyTier: HabitDifficultyTier? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> Habit? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }

        let now = Date()
        let habit = Habit(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            description: description,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            frequency: frequency,
            difficultyTier: difficultyTier
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

    func deleteHabit(id: String, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else {
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
            difficultyTier: existing.difficultyTier
        )

        mutateHabits { $0[index] = deleted }

        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func updateHabit(
        id: String,
        name: String? = nil,
        description: String? = nil,
        frequency: Double?? = nil,
        difficultyTier: HabitDifficultyTier?? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else {
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
            difficultyTier: difficultyTier ?? existing.difficultyTier
        )

        mutateHabits { $0[index] = updated }

        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func mergeHabits(_ remoteHabits: [Habit]) {
        guard !remoteHabits.isEmpty else { return }
        mutateHabits {
            $0 = mergeRecords(local: $0, remote: remoteHabits)
        }
    }

    func getDirtyHabits(ids: Set<String>) -> [Habit] {
        habits.filter { ids.contains($0.id) }
    }

    func purgeDeletedHabits() {
        mutateHabits {
            $0.removeAll { $0.deletedAt != nil }
        }
    }

    func allHabitIDs() -> [String] {
        habits.map(\.id)
    }

    private func mutateHabits(_ mutate: (inout [Habit]) -> Void) {
        var next = habits
        mutate(&next)
        next.sort { $0.createdAt < $1.createdAt }
        habits = next
        habitsByOwner[currentOwnerID] = next
        persist()
    }

    private func refreshCurrentHabits() {
        habits = habitsByOwner[currentOwnerID] ?? []
    }

    private func persist() {
        JSONFileStore.save(PersistedState(habitsByOwner: habitsByOwner), to: storageURL)
    }

    private func mergeRecords(local: [Habit], remote: [Habit]) -> [Habit] {
        var mergedByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for incoming in remote {
            if let existing = mergedByID[incoming.id], existing.updatedAt > incoming.updatedAt {
                continue
            }
            mergedByID[incoming.id] = incoming
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func notifySync(ids: [String]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .habits, recordIDs: ids))
    }
}
