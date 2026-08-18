import Foundation
import Testing
@testable import bochi

struct PremiumUpsellFeatureTests {

    // Behaviour: the premium modal should explain the specific locked feature
    // the user just tried, without turning the upsell into a long sales page.
    @Test("Each premium feature has short contextual upsell copy")
    func eachPremiumFeatureHasShortContextualUpsellCopy() {
        let expectedContexts: [PremiumUpsellFeature: String] = [
            .refunds: "Refund completed tasks when plans change or mistakes happen.",
            .sorting: "Sort lists your way so the next best task, recurring task, or reward is easier to find.",
            .dependencies: "Use dependencies to make tasks and rewards unlock only after prerequisite work is done.",
            .reminders: "Add reminders so recurring tasks and tasks come back when they need attention.",
            .lockouts: "Set lockouts to pace recurring tasks and rewards instead of repeating them too soon.",
            .timers: "Use timers to run focused sessions, duration countdowns, and multi-interval routines."
        ]

        for (feature, expectedContext) in expectedContexts {
            #expect(feature.contextDescription == expectedContext)
            #expect(sentenceCount(feature.contextDescription) <= 2)
        }
    }

    private func sentenceCount(_ text: String) -> Int {
        text
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }
}
