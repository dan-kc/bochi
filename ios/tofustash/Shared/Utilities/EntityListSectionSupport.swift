import Foundation

struct EntityListSectionModel<SectionID: Hashable, Item>: Identifiable {
    let id: SectionID
    let title: String?
    let isDimmed: Bool
    let items: [Item]
}

enum TaskListSectionID: Hashable {
    case defaultItems
    case blockedByDependency
    case completed
}

enum HabitListSectionID: Hashable {
    case defaultItems
    case locked
}

enum RewardListSectionID: Hashable {
    case defaultItems
    case locked
}

enum EntityListSectionSupport {
    static func taskSections(
        tasks: [TaskItem],
        taskStore: TaskStore,
        tradeStore: TradeStore,
        taskDependencyStore: TaskDependencyStore
    ) -> [EntityListSectionModel<TaskListSectionID, TaskItem>] {
        buildSections(
            items: tasks,
            definitions: [
                SectionDefinition(id: .defaultItems, title: nil, isDimmed: false) { task in
                    !isCompletedTask(task, tradeStore: tradeStore)
                        && !taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore)
                },
                SectionDefinition(id: .blockedByDependency, title: "Blocked by dependency", isDimmed: true) { task in
                    !isCompletedTask(task, tradeStore: tradeStore)
                        && taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore)
                },
                SectionDefinition(id: .completed, title: "Completed", isDimmed: true) { task in
                    isCompletedTask(task, tradeStore: tradeStore)
                }
            ]
        )
    }

    static func habitSections(
        habits: [Habit],
        tradeStore: TradeStore
    ) -> [EntityListSectionModel<HabitListSectionID, Habit>] {
        buildSections(
            items: habits,
            definitions: [
                SectionDefinition(id: .defaultItems, title: nil, isDimmed: false) { habit in
                    !HabitLockout.isLocked(habit: habit, tradeStore: tradeStore)
                },
                SectionDefinition(id: .locked, title: "Locked", isDimmed: true) { habit in
                    HabitLockout.isLocked(habit: habit, tradeStore: tradeStore)
                }
            ]
        )
    }

    static func rewardSections(
        rewards: [Reward],
        tradeStore: TradeStore
    ) -> [EntityListSectionModel<RewardListSectionID, Reward>] {
        buildSections(
            items: rewards,
            definitions: [
                SectionDefinition(id: .defaultItems, title: nil, isDimmed: false) { reward in
                    !RewardLockout.isLocked(reward: reward, tradeStore: tradeStore)
                },
                SectionDefinition(id: .locked, title: "Locked", isDimmed: true) { reward in
                    RewardLockout.isLocked(reward: reward, tradeStore: tradeStore)
                }
            ]
        )
    }

    private static func isCompletedTask(_ task: TaskItem, tradeStore: TradeStore) -> Bool {
        task.completedAt != nil || tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) != nil
    }

    private static func buildSections<Item, SectionID: Hashable>(
        items: [Item],
        definitions: [SectionDefinition<SectionID, Item>]
    ) -> [EntityListSectionModel<SectionID, Item>] {
        var itemsBySectionID: [SectionID: [Item]] = [:]

        for item in items {
            guard let section = definitions.first(where: { $0.matches(item) }) else { continue }
            itemsBySectionID[section.id, default: []].append(item)
        }

        return definitions.compactMap { definition in
            guard let sectionItems = itemsBySectionID[definition.id], !sectionItems.isEmpty else {
                return nil
            }

            return EntityListSectionModel(
                id: definition.id,
                title: definition.title,
                isDimmed: definition.isDimmed,
                items: sectionItems
            )
        }
    }
}

private struct SectionDefinition<SectionID: Hashable, Item> {
    let id: SectionID
    let title: String?
    let isDimmed: Bool
    let matches: (Item) -> Bool
}
