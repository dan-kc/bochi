import Foundation

// Small adapters for the repeated "only compute the amount when this entity is
// actionable" rule shared by earning and spending flows.
enum EntityActionSupport {
    static func sortableAmount(
        isActionable: Bool,
        calculate: () -> Int
    ) -> Int? {
        guard isActionable else { return nil }
        return calculate()
    }

    static func visibleAmount(
        isActionable: Bool,
        calculate: () -> Int
    ) -> Int {
        guard isActionable else { return 0 }
        return calculate()
    }
}
