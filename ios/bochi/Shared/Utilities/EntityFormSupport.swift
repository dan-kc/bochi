import Foundation

// Shared form helpers for task/reward editing. The goal is to centralize the
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
                isPremiumLocked: config.isPremiumLocked,
                requiresAttention: config.requiresAttention,
                action: actions[config.id]
            )
        }
    }

    static func premiumRenewalNotices(for pills: [PillItem]) -> [String] {
        pills.compactMap { pill in
            guard pill.isSet && pill.isPremiumLocked else { return nil }

            switch pill.id {
            case "reminders":
                return "Your existing reminders will return on premium renewal."
            case "lockout":
                return "Your existing lockout will return on premium renewal."
            case "dependencies":
                return "Your existing dependencies will return on premium renewal."
            case "timer":
                return "Your existing timer will return on premium renewal."
            case "adjustment":
                return "Your existing adjustment will return on premium renewal."
            default:
                return nil
            }
        }
    }
}

struct EntityFormPillConfig: Equatable {
    let id: String
    let label: String
    let icon: String
    let isSet: Bool
    var isPremiumLocked: Bool = false
    var requiresAttention: Bool = false
}
