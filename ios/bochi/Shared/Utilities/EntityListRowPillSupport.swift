import Foundation

enum EntityListRowPill: Equatable {
    case formItem(EntityFormPillConfig)
    case tag(Tag)
}

enum EntityListRowCadence: Equatable {
    case recurring
    case oneTime
}

struct EntityListRowMetadataItem: Equatable, Identifiable {
    let id: String
    let label: String?
    let icon: String
    let accessibilityLabel: String
}

enum EntityListRowPillSupport {
    static func taskMetadata(task: TaskItem) -> [EntityListRowMetadataItem] {
        metadataItems(cadence: .oneTime, isPinned: task.pinned)
    }

    static func recurringTaskMetadata(recurringTask: RecurringTask) -> [EntityListRowMetadataItem] {
        metadataItems(cadence: .recurring, isPinned: recurringTask.pinned)
    }

    static func rewardMetadata(reward: Reward) -> [EntityListRowMetadataItem] {
        metadataItems(cadence: reward.recurring ? .recurring : .oneTime, isPinned: reward.pinned)
    }

    static func taskPills(task: TaskItem, tags: [Tag]) -> [EntityListRowPill] {
        tags.map(EntityListRowPill.tag)
    }

    static func recurringTaskPills(recurringTask: RecurringTask, tags: [Tag]) -> [EntityListRowPill] {
        formItems(
            RecurringTaskFormView.buildPricePillData(
                basePrice: recurringTask.basePrice,
                frequency: recurringTask.frequency
            ),
            listLabelsByID: [:]
        ) + tags.map(EntityListRowPill.tag)
    }

    static func rewardPills(reward: Reward, tags: [Tag]) -> [EntityListRowPill] {
        formItems(
            RewardFormView.buildPricePillData(
                basePrice: reward.basePrice,
                maxFrequency: reward.maxFrequency
            ),
            listLabelsByID: [:]
        ) + tags.map(EntityListRowPill.tag)
    }

    private static func metadataItems(
        cadence: EntityListRowCadence,
        isPinned: Bool
    ) -> [EntityListRowMetadataItem] {
        var items = [cadenceMetadataItem(cadence)]

        if isPinned {
            items.append(
                EntityListRowMetadataItem(
                    id: "pinned",
                    label: nil,
                    icon: "pin.fill",
                    accessibilityLabel: "Pinned"
                )
            )
        }

        return items
    }

    private static func cadenceMetadataItem(_ cadence: EntityListRowCadence) -> EntityListRowMetadataItem {
        switch cadence {
        case .recurring:
            EntityListRowMetadataItem(
                id: "cadence",
                label: "Recurring",
                icon: "repeat",
                accessibilityLabel: "Recurring"
            )
        case .oneTime:
            EntityListRowMetadataItem(
                id: "cadence",
                label: "One-time",
                icon: "1.circle",
                accessibilityLabel: "One-time"
            )
        }
    }

    private static func formItems(
        _ configs: [EntityFormPillConfig],
        listLabelsByID: [String: String] = [:]
    ) -> [EntityListRowPill] {
        configs.compactMap { config in
            guard config.id != "price" else { return nil }
            guard config.id != "adjustment" || config.isSet else { return nil }
            guard config.id != "frequency" || config.isSet else { return nil }
            return EntityListRowPill.formItem(
                EntityFormPillConfig(
                    id: config.id,
                    label: config.isSet ? (listLabelsByID[config.id] ?? config.label) : "Unset",
                    icon: config.icon,
                    isSet: config.isSet,
                    isPremiumLocked: config.isPremiumLocked
                )
            )
        }
    }

    nonisolated private static func ratingLabel(_ tier: RecurringTaskDifficultyTier) -> String {
        switch tier {
        case .trivial: "1/5"
        case .light: "2/5"
        case .medium: "3/5"
        case .hard: "4/5"
        case .extreme: "5/5"
        }
    }

    nonisolated private static func ratingLabel(_ tier: RewardDamageTier) -> String {
        switch tier {
        case .harmless: "1/5"
        case .light: "2/5"
        case .medium: "3/5"
        case .heavy: "4/5"
        case .extreme: "5/5"
        }
    }

    nonisolated private static func ratingLabel(_ value: Int) -> String {
        "\(value)/5"
    }
}
