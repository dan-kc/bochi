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

    // Behaviour: pill-building should preserve the configured label, icon, and
    // action state without adding extra presentation-only metadata.
    @Test func buildPillsPreservesConfiguredPillState() {
        let pills = EntityFormSupport.buildPills(
            configs: [
                EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: true),
                EntityFormPillConfig(id: "frequency", label: "Frequency", icon: "clock", isSet: false),
            ],
            actions: [:]
        )

        #expect(pills[0].id == "tags")
        #expect(pills[0].label == "Tags")
        #expect(pills[0].icon == "tag")
        #expect(pills[0].isSet == true)
        #expect(pills[1].id == "frequency")
        #expect(pills[1].label == "Frequency")
        #expect(pills[1].icon == "clock")
        #expect(pills[1].isSet == false)
    }
}
