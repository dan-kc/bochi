import Foundation

enum SpecialOfferSupport {
    nonisolated static func adjustedAmount(
        baseAmount: Int,
        specialOfferModifierPercent: Int?
    ) -> Int {
        guard let specialOfferModifierPercent else { return baseAmount }
        let multiplier = 1.0 + (Double(specialOfferModifierPercent) / 100.0)
        return Int((Double(baseAmount) * multiplier).rounded())
    }

    nonisolated static func badgeText(modifierPercent: Int) -> String {
        modifierPercent > 0
            ? "Special +\(modifierPercent)%"
            : "Special \(modifierPercent)%"
    }
}
