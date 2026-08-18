import Testing
@testable import bochi

struct EntityActionGateSupportTests {
    // Behaviour: when an entity is both locked and hidden, the user should see
    // the lock warning because that is the stronger reason to pause.
    @Test func lockedTakesPriorityOverHidden() {
        let reason = EntityActionGateSupport.reason(
            isLocked: true,
            lockoutSummary: "42m",
            isHidden: true
        )

        #expect(reason == .locked(summary: "42m"))
        #expect(reason?.actionTitle(defaultTitle: "Buy Reward") == "Locked")
    }

    // Behaviour: hidden actions should keep showing the amount while naming
    // the hidden state on expanded form buttons.
    @Test func hiddenActionUsesHiddenTitle() {
        let reason = EntityActionGateSupport.reason(isLocked: false, isHidden: true)

        #expect(reason == .hidden)
        #expect(reason?.actionTitle(defaultTitle: "Buy Reward") == "Hidden")
    }

    // Behaviour: normal actions keep their domain-specific button wording.
    @Test func unrestrictedActionKeepsDefaultTitle() {
        let reason = EntityActionGateSupport.reason(isLocked: false, isHidden: false)

        #expect(reason == nil)
        #expect(EntityActionGateSupport.actionTitle(defaultTitle: "Complete Task", reason: reason) == "Complete Task")
    }
}
