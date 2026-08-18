import Foundation
import FuzzyMatch

nonisolated enum OmniSearchResultID: Hashable, Sendable {
    case task(RecordID)
    case recurringTask(RecordID)
    case reward(RecordID)
}

nonisolated struct OmniSearchSnapshot: Equatable, Sendable {
    let results: [OmniSearchResult]
    let message: String?

    init(results: [OmniSearchResult], message: String? = nil) {
        self.results = results
        self.message = message
    }
}

nonisolated enum OmniSearchResult: Identifiable, Equatable, Sendable {
    case task(TaskItem)
    case recurringTask(RecurringTask)
    case reward(Reward)

    var id: OmniSearchResultID {
        switch self {
        case .task(let task):
            return .task(task.id)
        case .recurringTask(let recurringTask):
            return .recurringTask(recurringTask.id)
        case .reward(let reward):
            return .reward(reward.id)
        }
    }
}

nonisolated struct OmniSearchQueryHighlight: Equatable, Sendable {
    let text: String
    let colorHex: String
    let start: Int
    let length: Int
}

enum OmniSearchSupport {
    nonisolated static let emptyQueryMessage = "Search tasks, recurring tasks, and rewards by name."

    nonisolated static func makeSnapshot(
        tasks: [TaskItem],
        recurringTasks: [RecurringTask],
        rewards: [Reward],
        queryText: String,
        taskTagsByID: [RecordID: [Tag]] = [:],
        recurringTaskTagsByID: [RecordID: [Tag]] = [:],
        rewardTagsByID: [RecordID: [Tag]] = [:],
        completedTaskIDs: Set<RecordID> = [],
        completedRewardIDs: Set<RecordID> = [],
        lockedTaskIDs: Set<RecordID> = [],
        lockedRecurringTaskIDs: Set<RecordID>? = nil,
        lockedRewardIDs: Set<RecordID>? = nil,
        hiddenStatusFilters: Set<EntityListStatusFilter> = [],
        hiddenTagIDs: Set<RecordID> = [],
        availableTags: [Tag]? = nil
    ) -> OmniSearchSnapshot {
        let matcher = FuzzyMatcher()
        let trimmedQueryText = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQueryText.isEmpty else {
            return OmniSearchSnapshot(results: [], message: emptyQueryMessage)
        }

        let query = matcher.prepare(trimmedQueryText)
        var buffer = matcher.makeBuffer()

        let taskResults = scoredMatches(
            items: tasks.filter {
                let tags = taskTagsByID[$0.id] ?? []

                return $0.deletedAt == nil
                    && matchesStatuses(
                        taskStatuses(
                            $0,
                            completedTaskIDs: completedTaskIDs,
                            lockedTaskIDs: lockedTaskIDs
                        ),
                        hiddenStatusFilters: hiddenStatusFilters
                    )
                    && matchesTags(tags, hiddenTagIDs: hiddenTagIDs)
            },
            sourceOffset: 0,
            query: query,
            matcher: matcher,
            buffer: &buffer,
            name: \.name,
            result: OmniSearchResult.task
        )
        let recurringTaskResults = scoredMatches(
            items: recurringTasks.filter {
                let isLocked = lockedRecurringTaskIDs?.contains($0.id) ?? (($0.lockoutDurationSeconds ?? 0) > 0)
                let tags = recurringTaskTagsByID[$0.id] ?? []

                return $0.deletedAt == nil
                    && matchesStatuses(
                        recurringTaskStatuses($0, isLocked: isLocked),
                        hiddenStatusFilters: hiddenStatusFilters
                    )
                    && matchesTags(tags, hiddenTagIDs: hiddenTagIDs)
            },
            sourceOffset: tasks.count,
            query: query,
            matcher: matcher,
            buffer: &buffer,
            name: \.name,
            result: OmniSearchResult.recurringTask
        )
        let rewardResults = scoredMatches(
            items: rewards.filter {
                let isLocked = lockedRewardIDs?.contains($0.id) ?? (($0.lockoutDurationSeconds ?? 0) > 0)
                let tags = rewardTagsByID[$0.id] ?? []

                return $0.deletedAt == nil
                    && matchesStatuses(
                        rewardStatuses(
                            $0,
                            isLocked: isLocked,
                            completedRewardIDs: completedRewardIDs
                        ),
                        hiddenStatusFilters: hiddenStatusFilters
                    )
                    && matchesTags(tags, hiddenTagIDs: hiddenTagIDs)
            },
            sourceOffset: tasks.count + recurringTasks.count,
            query: query,
            matcher: matcher,
            buffer: &buffer,
            name: \.name,
            result: OmniSearchResult.reward
        )

        return OmniSearchSnapshot(
            results: (taskResults + recurringTaskResults + rewardResults)
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score {
                        return lhs.score > rhs.score
                    }

                    return lhs.sourceIndex < rhs.sourceIndex
                }
                .map(\.result)
        )
    }

    nonisolated static func queryHighlights(queryText: String, availableTags: [Tag]) -> [OmniSearchQueryHighlight] {
        []
    }

    nonisolated static func queryRequiresLockedFilter(_ queryText: String) -> Bool {
        false
    }

    nonisolated static func warmUpMatcher() {
        let matcher = FuzzyMatcher()
        let query = matcher.prepare("search")
        var buffer = matcher.makeBuffer()
        _ = matcher.score("search", against: query, buffer: &buffer)
    }

    nonisolated private static func scoredMatches<Item>(
        items: [Item],
        sourceOffset: Int,
        query: FuzzyQuery?,
        matcher: FuzzyMatcher,
        buffer: inout ScoringBuffer,
        name: KeyPath<Item, String>,
        result: (Item) -> OmniSearchResult
    ) -> [(sourceIndex: Int, result: OmniSearchResult, score: Double)] {
        items.enumerated().compactMap { index, item in
            guard let query else {
                return (
                    sourceIndex: sourceOffset + index,
                    result: result(item),
                    score: 0
                )
            }

            guard let match = matcher.score(item[keyPath: name], against: query, buffer: &buffer) else {
                return nil
            }

            return (
                sourceIndex: sourceOffset + index,
                result: result(item),
                score: match.score
            )
        }
    }

    nonisolated private static func taskStatuses(
        _ task: TaskItem,
        completedTaskIDs: Set<RecordID>,
        lockedTaskIDs: Set<RecordID>
    ) -> Set<EntityListStatusFilter> {
        var statuses: Set<EntityListStatusFilter> = [
            .taskGroup,
            .task,
            completedTaskIDs.contains(task.id) ? .completed : .incomplete
        ]
        if task.hidden {
            statuses.insert(.hidden)
        }
        if lockedTaskIDs.contains(task.id) {
            statuses.insert(.locked)
        }
        return statuses
    }

    nonisolated private static func recurringTaskStatuses(
        _ recurringTask: RecurringTask,
        isLocked: Bool
    ) -> Set<EntityListStatusFilter> {
        var statuses: Set<EntityListStatusFilter> = [.taskGroup, .recurringTask]
        if recurringTask.hidden {
            statuses.insert(.hidden)
        }
        if isLocked {
            statuses.insert(.locked)
        }
        return statuses
    }

    nonisolated private static func rewardStatuses(
        _ reward: Reward,
        isLocked: Bool,
        completedRewardIDs: Set<RecordID>
    ) -> Set<EntityListStatusFilter> {
        var statuses: Set<EntityListStatusFilter> = [.reward]
        if reward.hidden {
            statuses.insert(.hidden)
        }
        if isLocked {
            statuses.insert(.locked)
        }
        if completedRewardIDs.contains(reward.id) {
            statuses.insert(.completed)
        }
        return statuses
    }

    nonisolated private static func matchesStatuses(
        _ statuses: Set<EntityListStatusFilter>,
        hiddenStatusFilters: Set<EntityListStatusFilter>
    ) -> Bool {
        statuses.isDisjoint(with: hiddenStatusFilters)
    }

    nonisolated private static func matchesTags(_ itemTags: [Tag], hiddenTagIDs: Set<RecordID>) -> Bool {
        guard !hiddenTagIDs.isEmpty else { return true }
        return itemTags.map(\.id).allSatisfy { !hiddenTagIDs.contains($0) }
    }
}
