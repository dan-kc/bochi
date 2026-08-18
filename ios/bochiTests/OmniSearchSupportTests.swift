import Foundation
import Testing
@testable import bochi

struct OmniSearchSupportTests {
    // Behaviour: opening omni search should not show every item in the app;
    // users get a focused prompt until they type a name to search for.
    @Test("Blank query invites typing without results")
    func blankQueryInvitesTypingWithoutResults() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [
                makeTask(id: "task-read", name: "Read paper"),
                makeTask(id: "task-done", name: "Read archived")
            ],
            recurringTasks: [makeRecurringTask(id: "recurringTask-read", name: "Reading")],
            rewards: [makeReward(id: "reward-read", name: "Reading break")],
            queryText: "   ",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:],
            completedTaskIDs: ["task-done"],
            hiddenStatusFilters: [.completed]
        )

        #expect(snapshot.results.isEmpty)
        #expect(snapshot.message == "Search tasks, recurring tasks, and rewards by name.")
    }

    // Behaviour: one omni query should search every entity category at once so
    // users do not have to remember which tab owns the thing they wanted.
    @Test("Query searches tasks recurring tasks and rewards")
    func querySearchesAllCategories() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [
                makeTask(id: "task-read", name: "Read paper"),
                makeTask(id: "task-buy", name: "Buy milk")
            ],
            recurringTasks: [
                makeRecurringTask(id: "recurringTask-read", name: "Reading"),
                makeRecurringTask(id: "recurringTask-walk", name: "Walk")
            ],
            rewards: [
                makeReward(id: "reward-read", name: "Reading break"),
                makeReward(id: "reward-tv", name: "TV")
            ],
            queryText: "read",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:]
        )

        #expect(Set(snapshot.resultLabels) == [
            "task:task-read",
            "recurringTask:recurringtask-read",
            "reward:reward-read"
        ])
        #expect(snapshot.results.count == 3)
    }

    // Behaviour: search results should be one fat relevance-ranked list, not
    // three category buckets that hide a stronger reward below weaker tasks.
    @Test("Results are globally ranked across entity types")
    func resultsAreGloballyRankedAcrossEntityTypes() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [
                makeTask(id: "task-weak", name: "Read the long weekly planning packet")
            ],
            recurringTasks: [
                makeRecurringTask(id: "recurringTask-medium", name: "Reading")
            ],
            rewards: [
                makeReward(id: "reward-best", name: "Read")
            ],
            queryText: "read",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:]
        )

        #expect(snapshot.resultLabels == [
            "reward:reward-best",
            "recurringTask:recurringtask-medium",
            "task:task-weak"
        ])
    }

    // Behaviour: search should survive small typing mistakes instead of
    // requiring exact spelling while the user is typing on a phone keyboard.
    @Test("Fuzzy query tolerates fat finger spelling")
    func fuzzyQueryToleratesFatFingerSpelling() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [
                makeTask(id: "task-read", name: "Read paper"),
                makeTask(id: "task-pay", name: "Pay rent")
            ],
            recurringTasks: [],
            rewards: [],
            queryText: "reed",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:]
        )

        #expect(snapshot.resultLabels == ["task:task-read"])
    }

    // Behaviour: deleted records stay hidden, while locked and pinned records
    // remain searchable by default; completed visibility comes from controls.
    @Test("Query includes locked and pinned while completed control hides completed tasks")
    func queryIncludesLockedAndPinnedWhileCompletedControlHidesCompletedTasks() {
        let completedTask = makeTask(id: "task-done", name: "Archive receipt")
        let deletedTask = makeTask(id: "task-deleted", name: "Archive deleted", deletedAt: date(day: 5))
        let pinnedTask = makeTask(id: "task-pinned", name: "Archive pinned", pinned: true)
        let lockedRecurringTask = makeRecurringTask(id: "recurringTask-locked", name: "Archive recurringTask", lockoutDurationSeconds: 3_600)
        let lockedReward = makeReward(id: "reward-locked", name: "Archive reward", lockoutDurationSeconds: 3_600, pinned: true)

        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [completedTask, deletedTask, pinnedTask],
            recurringTasks: [lockedRecurringTask],
            rewards: [lockedReward],
            queryText: "archive",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:],
            completedTaskIDs: ["task-done"],
            hiddenStatusFilters: [.completed]
        )

        #expect(Set(snapshot.resultLabels) == [
            "task:task-pinned",
            "recurringTask:recurringtask-locked",
            "reward:reward-locked"
        ])
        #expect(snapshot.resultLabels.contains("task:task-deleted") == false)
        #expect(snapshot.resultLabels.contains("task:task-done") == false)
    }

    // Behaviour: entity type chips should narrow typed search results without
    // users needing to type command-like filters into the search field.
    @Test("Entity controls narrow typed results")
    func entityControlsNarrowTypedResults() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [makeTask(id: "task-read", name: "Read paper")],
            recurringTasks: [makeRecurringTask(id: "recurringTask-read", name: "Reading")],
            rewards: [makeReward(id: "reward-read", name: "Reading break")],
            queryText: "read",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:],
            hiddenStatusFilters: [.task, .reward]
        )

        #expect(snapshot.resultLabels == ["recurringTask:recurringtask-read"])
    }

    // Behaviour: the search Task chip hides all task-like work while keeping
    // the separate Reward chip available for spending results.
    @Test("Task group control hides one-time and recurring search results")
    func taskGroupControlHidesOneOffAndRecurringSearchResults() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [makeTask(id: "task-read", name: "Read paper")],
            recurringTasks: [makeRecurringTask(id: "recurringTask-read", name: "Reading")],
            rewards: [makeReward(id: "reward-read", name: "Reading break")],
            queryText: "read",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:],
            hiddenStatusFilters: [.taskGroup]
        )

        #expect(snapshot.resultLabels == ["reward:reward-read"])
    }

    // Behaviour: tag chips should filter every entity category by assignments,
    // while the search field remains plain name search.
    @Test("Tag controls filter across entity tags")
    func tagControlsFilterAcrossEntityTags() {
        let focus = makeTag(id: "tag-focus", name: "Focus", colorHex: "#FF0000")
        let chores = makeTag(id: "tag-chores", name: "Chores", colorHex: "#00FF00")

        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [
                makeTask(id: "task-focus", name: "Focus bill"),
                makeTask(id: "task-chores", name: "Focus bill")
            ],
            recurringTasks: [makeRecurringTask(id: "recurringTask-focus", name: "Focus recurringTask")],
            rewards: [makeReward(id: "reward-focus", name: "Focus coffee")],
            queryText: "focus",
            taskTagsByID: [
                "task-focus": [focus],
                "task-chores": [chores]
            ],
            recurringTaskTagsByID: ["recurringTask-focus": [focus]],
            rewardTagsByID: ["reward-focus": [focus]],
            hiddenTagIDs: [chores.id]
        )

        #expect(Set(snapshot.resultLabels) == [
            "task:task-focus",
            "recurringTask:recurringtask-focus",
            "reward:reward-focus"
        ])
    }

    // Behaviour: disabling multiple tags should hide rows carrying any disabled
    // tag, matching the spend and earn control semantics.
    @Test("Multiple tag controls hide any matching rows")
    func multipleTagControlsHideAnyMatchingRows() {
        let focus = makeTag(id: "tag-focus", name: "Focus", colorHex: "#FF0000")
        let morning = makeTag(id: "tag-morning", name: "Morning", colorHex: "#00FF00")

        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [
                makeTask(id: "task-both", name: "Focus plan"),
                makeTask(id: "task-focus", name: "Focus work"),
                makeTask(id: "task-morning", name: "Focus stretch"),
                makeTask(id: "task-open", name: "Focus read")
            ],
            recurringTasks: [makeRecurringTask(id: "recurringTask-both", name: "Focus journal")],
            rewards: [makeReward(id: "reward-focus", name: "Focus coffee")],
            queryText: "focus",
            taskTagsByID: [
                "task-both": [focus, morning],
                "task-focus": [focus],
                "task-morning": [morning],
                "task-open": []
            ],
            recurringTaskTagsByID: ["recurringTask-both": [focus, morning]],
            rewardTagsByID: ["reward-focus": [focus]],
            hiddenTagIDs: [focus.id, morning.id]
        )

        #expect(snapshot.resultLabels == ["task:task-open"])
    }

    // Behaviour: hashtag-looking text should behave like any other search text
    // because tag filtering now lives in the controls row.
    @Test("Hashtag text is plain search text")
    func hashtagTextIsPlainSearchText() {
        let focus = makeTag(id: "tag-focus", name: "Focus", colorHex: "#FF0000")

        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [makeTask(id: "task-focus", name: "Plan day")],
            recurringTasks: [],
            rewards: [],
            queryText: "#tag-that-does-not-exist",
            taskTagsByID: ["task-focus": [focus]],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:]
        )

        #expect(snapshot.results.isEmpty)
        #expect(snapshot.message == nil)
    }

    // Behaviour: command-looking type text should not secretly change result
    // categories now that type filtering lives in the control bar.
    @Test("Type command text is plain search text")
    func typeCommandTextIsPlainSearchText() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [makeTask(id: "task-read", name: "Read paper")],
            recurringTasks: [makeRecurringTask(id: "recurringTask-read", name: "Reading")],
            rewards: [makeReward(id: "reward-read", name: "Reading break")],
            queryText: "type:recurringTask",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:]
        )

        #expect(snapshot.results.isEmpty)
        #expect(snapshot.message == nil)
    }

    // Behaviour: status chips should hide matching statuses using the same
    // visibility model as the spend and earn lists.
    @Test("Status controls hide matching rows")
    func statusControlsHideMatchingRows() {
        let completedHiddenSnapshot = OmniSearchSupport.makeSnapshot(
            tasks: [
                makeTask(id: "task-open", name: "Receipt"),
                makeTask(id: "task-done", name: "Receipt")
            ],
            recurringTasks: [makeRecurringTask(id: "recurringTask-receipt", name: "Receipt")],
            rewards: [makeReward(id: "reward-receipt", name: "Receipt")],
            queryText: "receipt",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:],
            completedTaskIDs: ["task-done"],
            hiddenStatusFilters: [.completed]
        )
        let lockedHiddenSnapshot = OmniSearchSupport.makeSnapshot(
            tasks: [makeTask(id: "task-open", name: "Receipt", pinned: true)],
            recurringTasks: [
                makeRecurringTask(id: "recurringTask-open", name: "Receipt"),
                makeRecurringTask(id: "recurringTask-locked", name: "Receipt", lockoutDurationSeconds: 3_600)
            ],
            rewards: [
                makeReward(id: "reward-open", name: "Receipt"),
                makeReward(id: "reward-locked", name: "Receipt", lockoutDurationSeconds: 3_600)
            ],
            queryText: "receipt",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:],
            hiddenStatusFilters: [.locked]
        )

        #expect(Set(completedHiddenSnapshot.resultLabels) == [
            "task:task-open",
            "recurringTask:recurringtask-receipt",
            "reward:reward-receipt"
        ])
        #expect(Set(lockedHiddenSnapshot.resultLabels) == [
            "task:task-open",
            "recurringTask:recurringtask-open",
            "reward:reward-open"
        ])
    }

    // Behaviour: completion can be mixed with any visible type because it is now
    // a status chip, not invalid syntax in the search text field.
    @Test("Completed control can be combined with non task types")
    func completedControlCanBeCombinedWithNonTaskTypes() {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: [makeTask(id: "task-done", name: "Receipt")],
            recurringTasks: [makeRecurringTask(id: "recurringTask-receipt", name: "Receipt")],
            rewards: [makeReward(id: "reward-receipt", name: "Receipt")],
            queryText: "receipt",
            taskTagsByID: [:],
            recurringTaskTagsByID: [:],
            rewardTagsByID: [:],
            completedTaskIDs: ["task-done"],
            hiddenStatusFilters: [.task, .reward]
        )

        #expect(snapshot.resultLabels == ["recurringTask:recurringtask-receipt"])
        #expect(snapshot.message == nil)
    }

    // Behaviour: typed filters no longer produce inline highlights because the
    // visible filter state lives in the controls row.
    @Test("Typed filter text produces no highlight metadata")
    func typedFilterTextProducesNoHighlightMetadata() {
        let focus = makeTag(id: "tag-focus", name: "Focus", colorHex: "#E5484D")

        let highlights = OmniSearchSupport.queryHighlights(
            queryText: "#focus type:task is:pinned read",
            availableTags: [focus]
        )

        #expect(highlights.isEmpty)
    }

    private func date(day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400))
    }

    private func makeTask(
        id: RecordID,
        name: String,
        createdAt: Date = Date(timeIntervalSince1970: 86_400),
        deletedAt: Date? = nil,
        pinned: Bool = false
    ) -> TaskItem {
        TaskItem(
            id: id,
            name: name,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: deletedAt,
            basePrice: 200,
            dueDate: nil,
            pinned: pinned
        )
    }

    private func makeRecurringTask(
        id: RecordID,
        name: String,
        createdAt: Date = Date(timeIntervalSince1970: 86_400),
        lockoutDurationSeconds: Int? = nil,
        pinned: Bool = false
    ) -> RecurringTask {
        RecurringTask(
            id: id,
            name: name,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            frequency: nil,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: 100,
            pinned: pinned
        )
    }

    private func makeReward(
        id: RecordID,
        name: String,
        createdAt: Date = Date(timeIntervalSince1970: 86_400),
        lockoutDurationSeconds: Int? = nil,
        pinned: Bool = false
    ) -> Reward {
        Reward(
            id: id,
            name: name,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            maxFrequency: nil,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: 500,
            pinned: pinned
        )
    }

    private func makeTag(id: RecordID, name: String, colorHex: String) -> bochi.Tag {
        bochi.Tag(
            id: id,
            name: name,
            colorHex: colorHex,
            createdAt: Date(timeIntervalSince1970: 86_400),
            updatedAt: Date(timeIntervalSince1970: 86_400),
            deletedAt: nil
        )
    }
}

private extension OmniSearchSnapshot {
    var resultLabels: [String] {
        results.map { result in
            switch result.id {
            case .task(let id):
                return "task:\(id.rawValue)"
            case .recurringTask(let id):
                return "recurringTask:\(id.rawValue)"
            case .reward(let id):
                return "reward:\(id.rawValue)"
            }
        }
    }
}
