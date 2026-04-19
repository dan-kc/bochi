import Foundation
import Testing
@testable import tofustash

struct EntityFormSupportTests {
    // Behaviour: when a user only types whitespace around a name, auto-save
    // should persist the intentional name instead of preserving the padding.
    @Test func trimmedNameRemovesOuterWhitespace() {
        #expect(EntityFormSupport.trimmedName("  Read  ") == "Read")
    }

    // Behaviour: dismissing a brand-new draft should only offer recovery after
    // the user entered something meaningful into the form.
    @Test func recoverableContentIgnoresBlankDraft() {
        #expect(EntityFormSupport.hasRecoverableContent(
            name: "",
            description: "",
            primaryValueIsSet: false,
            secondaryValueIsSet: false,
            tagCount: 0
        ) == false)
    }

    // Behaviour: first-run defaults should not create a fake recovery toast
    // before the user actually changes anything.
    @Test func recoverableContentCanIgnoreAutofilledSecondaryField() {
        #expect(EntityFormSupport.hasRecoverableContent(
            name: "",
            description: "",
            primaryValueIsSet: false,
            secondaryValueIsSet: true,
            tagCount: 0,
            ignoreSecondaryValue: true
        ) == false)
    }

    // Behaviour: unset required pills should animate attention while already
    // configured pills stay calm and tappable.
    @Test func buildPillsOnlyAnimatesRequestedUnsetPills() {
        let pills = EntityFormSupport.buildPills(
            configs: [
                EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: true),
                EntityFormPillConfig(id: "frequency", label: "Frequency", icon: "clock", isSet: false),
            ],
            animatedIDs: ["tags", "frequency"],
            actions: [:]
        )

        #expect(pills[0].animating == false)
        #expect(pills[1].animating == true)
    }
}
