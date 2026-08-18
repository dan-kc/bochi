import Foundation
import Testing
import UIKit
@testable import bochi

@MainActor
struct EntityListRowPillSupportTests {
    // Behaviour: List rows keep the full description text available to the
    // row, letting the view fade it near the trailing action.
    @Test("description line preserves long descriptions")
    func descriptionLinePreservesLongDescriptions() {
        #expect(
            EntityListRowDescriptionSupport.description(from: "Write the weekly reporting draft")
                == EntityListRowDescription(text: "Write the weekly reporting draft")
        )
    }

    // Behaviour: List rows do not reserve a description line when the user did
    // not add meaningful description text.
    @Test("description line is not rendered for blank descriptions")
    func descriptionLineIsNotRenderedForBlankDescriptions() {
        #expect(EntityListRowDescriptionSupport.description(from: " \n\t ") == nil)
    }

    // Behaviour: Description rows trim form-entry whitespace before rendering,
    // so copied text does not create invisible leading or trailing space.
    @Test("description line trims surrounding whitespace")
    func descriptionLineTrimsSurroundingWhitespace() {
        #expect(
            EntityListRowDescriptionSupport.description(from: "  123456789012345  ")
                == EntityListRowDescription(text: "123456789012345")
        )
    }

    // Behaviour: completed task names should keep the truncation ellipsis
    // readable instead of drawing the completion line through those dots.
    @Test("completed task strike line leaves truncated ellipsis clear")
    func completedTaskStrikeLineLeavesTruncatedEllipsisClear() {
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let availableWidth = textWidth("abc...", font: font)

        #expect(
            EntityListNameTruncationSupport.renderedName(
                "abcdefg",
                availableWidth: availableWidth,
                font: font
            ) == EntityListRenderedName(struckText: "abc", showsEllipsis: true)
        )
    }

    // Behaviour: completed task names that fit on screen should still strike
    // through the whole rendered title.
    @Test("completed task strike line covers names that fit")
    func completedTaskStrikeLineCoversNamesThatFit() {
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let availableWidth = textWidth("abcdefg", font: font)

        #expect(
            EntityListNameTruncationSupport.renderedName(
                "abcdefg",
                availableWidth: availableWidth,
                font: font
            ) == EntityListRenderedName(struckText: "abcdefg", showsEllipsis: false)
        )
    }

    // Behaviour: one-time tasks expose their cadence above the row name, and
    // the pin affordance appears only when the task has been pinned.
    @Test("task metadata shows one-time cadence and pinned state")
    func taskMetadataShowsOneTimeCadenceAndPinnedState() {
        let task = makeTask(id: "task-pinned", pinned: true)

        #expect(EntityListRowPillSupport.taskMetadata(task: task) == [
            EntityListRowMetadataItem(
                id: "cadence",
                label: "One-time",
                icon: "1.circle",
                accessibilityLabel: "One-time"
            ),
            EntityListRowMetadataItem(
                id: "pinned",
                label: nil,
                icon: "pin.fill",
                accessibilityLabel: "Pinned"
            )
        ])
    }

    // Behaviour: recurring recurringTasks always announce their recurring cadence, but
    // unpinned recurringTasks do not reserve a blank pinned icon slot.
    @Test("recurringTask metadata omits pinned icon when unpinned")
    func recurringTaskMetadataOmitsPinnedIconWhenUnpinned() {
        let recurringTask = makeRecurringTask(id: "recurringTask-unpinned")

        #expect(EntityListRowPillSupport.recurringTaskMetadata(recurringTask: recurringTask) == [
            EntityListRowMetadataItem(
                id: "cadence",
                label: "Recurring",
                icon: "repeat",
                accessibilityLabel: "Recurring"
            )
        ])
    }

    // Behaviour: rewards can be recurring or one-time independently of their
    // list, so their row metadata mirrors the reward cadence itself.
    @Test("reward metadata follows reward cadence")
    func rewardMetadataFollowsRewardCadence() {
        let reward = makeReward(id: "reward-one-time", recurring: false)

        #expect(EntityListRowPillSupport.rewardMetadata(reward: reward) == [
            EntityListRowMetadataItem(
                id: "cadence",
                label: "One-time",
                icon: "1.circle",
                accessibilityLabel: "One-time"
            )
        ])
    }

    // Behaviour: Task detail rows do not repeat the action price; they only
    // render applied tags.
    @Test("task detail rows show tags without price")
    func taskDetailRowsShowTagsWithoutPrice() {
        let focus = makeTag(id: "focus", name: "Focus")
        let deepWork = makeTag(id: "deep-work", name: "Deep Work")
        let task = makeTask(id: "task-1", basePrice: 275)

        let pills = EntityListRowPillSupport.taskPills(task: task, tags: [focus, deepWork])

        #expect(pills == [
            .tag(focus),
            .tag(deepWork)
        ])
    }

    // Behaviour: Task rows do not reserve a blank details strip when there is
    // no frequency concept and the user has not applied tags.
    @Test("task detail rows are empty when no tags exist")
    func taskDetailRowsAreEmptyWhenNoTagsExist() {
        let task = makeTask(id: "task-blank", basePrice: 200)

        #expect(EntityListRowPillSupport.taskPills(task: task, tags: []) == [])
    }

    // Behaviour: Tags shown in list row details keep the same saved tag color
    // as the edit form chips, even when the surrounding row uses role colors.
    @Test("list row tag pills use saved tag colors")
    func listRowTagPillsUseSavedTagColors() {
        let tag = makeTag(
            id: "tag-focus",
            name: "Focus",
            colorHex: BochiTheme.tagPickerStoredHex(for: .red)
        )

        let style = EntityListTagPillStyle.style(
            for: tag,
            role: .reward,
            colorStrategy: .rolePalette
        )

        #expect(style.colorSource == .tag(colorHex: tag.colorHex))
        #expect(style.showsBorder == false)
    }

    // Behaviour: RecurringTask rows show configured minimum frequency before tags
    // without repeating the submitted base price.
    @Test("recurringTask detail rows show min frequency before tags")
    func recurringTaskDetailRowsShowMinFrequencyBeforeTags() {
        let health = makeTag(id: "health", name: "Health")
        let recurringTask = makeRecurringTask(id: "recurringTask-1", frequency: 1.0 / 7.0, basePrice: 120)

        let pills = EntityListRowPillSupport.recurringTaskPills(recurringTask: recurringTask, tags: [health])

        #expect(pills == [
            .formItem(EntityFormPillConfig(id: "frequency", label: "Min 1/week", icon: "clock", isSet: true)),
            .tag(health)
        ])
    }

    // Behaviour: Recurring task rows do not reserve the details strip for one-time
    // recurringTasks with no tags.
    @Test("recurringTask detail rows are empty without frequency or tags")
    func recurringTaskDetailRowsAreEmptyWithoutFrequencyOrTags() {
        let recurringTask = makeRecurringTask(id: "recurringTask-blank", frequency: nil, basePrice: 100)

        #expect(EntityListRowPillSupport.recurringTaskPills(recurringTask: recurringTask, tags: []) == [])
    }

    // Behaviour: Reward rows show configured max frequency before tags without
    // repeating the submitted base price.
    @Test("reward detail rows show max frequency before tags")
    func rewardDetailRowsShowMaxFrequencyBeforeTags() {
        let leisure = makeTag(id: "leisure", name: "Leisure")
        let reward = makeReward(id: "reward-1", maxFrequency: 1.0 / 7.0, basePrice: 450)

        let pills = EntityListRowPillSupport.rewardPills(reward: reward, tags: [leisure])

        #expect(pills == [
            .formItem(EntityFormPillConfig(id: "frequency", label: "Max 1/week", icon: "clock", isSet: true)),
            .tag(leisure)
        ])
    }

    // Behaviour: Reward rows do not reserve the details strip for one-time
    // rewards with no tags.
    @Test("reward detail rows are empty without frequency or tags")
    func rewardDetailRowsAreEmptyWithoutFrequencyOrTags() {
        let reward = makeReward(id: "reward-blank", maxFrequency: nil, basePrice: 500)

        #expect(EntityListRowPillSupport.rewardPills(reward: reward, tags: []) == [])
    }

    private func textWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

private func makeTask(
    id: RecordID,
    basePrice: Int = 200,
    pinned: Bool = false
) -> TaskItem {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    return TaskItem(
        id: id,
        name: "Task",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: nil,
        basePrice: basePrice,
        dueDate: nil,
        pinned: pinned
    )
}

private func makeRecurringTask(
    id: RecordID,
    frequency: Double? = nil,
    basePrice: Int = 100
) -> RecurringTask {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    return RecurringTask(
        id: id,
        name: "RecurringTask",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: nil,
        frequency: frequency,
        basePrice: basePrice
    )
}

private func makeReward(
    id: RecordID,
    recurring: Bool = true,
    maxFrequency: Double? = nil,
    basePrice: Int = 500
) -> Reward {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    return Reward(
        id: id,
        recurring: recurring,
        name: "Reward",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: nil,
        maxFrequency: maxFrequency,
        basePrice: basePrice
    )
}

private func makeTag(
    id: RecordID,
    name: String,
    colorHex: String = "#336699"
) -> bochi.Tag {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    return bochi.Tag(
        id: id,
        name: name,
        colorHex: colorHex,
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: nil
    )
}
