import Foundation

// Shared form helpers for habit/reward editing. The goal is to centralize the
// repeated draft rules while keeping each feature's view readable in its own
// domain language.
enum EntityFormSupport {
    static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
    }

    static func hasRecoverableContent(
        name: String,
        description: String,
        primaryValueIsSet: Bool,
        secondaryValueIsSet: Bool,
        tagCount: Int,
        ignoreSecondaryValue: Bool = false
    ) -> Bool {
        let hasSecondaryValue = ignoreSecondaryValue ? false : secondaryValueIsSet

        return !name.isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || primaryValueIsSet
            || hasSecondaryValue
            || tagCount > 0
    }

    static func buildPills(
        configs: [EntityFormPillConfig],
        actions: [String: () -> Void]
    ) -> [PillItem] {
        configs.map { config in
            PillItem(
                id: config.id,
                label: config.label,
                icon: config.icon,
                isSet: config.isSet,
                action: actions[config.id]
            )
        }
    }
}

struct EntityFormPillConfig: Equatable {
    let id: String
    let label: String
    let icon: String
    let isSet: Bool
}
