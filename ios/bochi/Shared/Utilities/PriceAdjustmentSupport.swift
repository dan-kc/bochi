import Foundation

enum PriceAdjustmentSupport {
    nonisolated static let minimumMultiplier = 0.0
    nonisolated static let maximumMultiplier = Double(BackendIntegerContract.max)

    nonisolated static func adjustedRoundedAmount(
        _ rawAmount: Double,
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        BackendIntegerContract.clampedNonNegative(adjustedAmount(
            rawAmount,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        ))
    }

    nonisolated static func adjustedAmount(
        _ rawAmount: Double,
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Double {
        var amount = rawAmount.rounded()
        if hasPremiumAccess {
            if let oneTimeAdjustmentMultiplier {
                amount *= oneTimeAdjustmentMultiplier
            }
        }
        return min(max(amount, 0), Double(BackendIntegerContract.max))
    }

    nonisolated static func validated(_ multiplier: Double?) -> Double? {
        guard let multiplier else { return nil }
        guard (minimumMultiplier...maximumMultiplier).contains(multiplier) else { return nil }
        return multiplier
    }

    nonisolated static func multiplier(forAdjustedPrice adjustedPrice: Int, basePrice: Int) -> Double? {
        let clampedAdjustedPrice = BackendIntegerContract.clampedNonNegative(adjustedPrice)
        let clampedBasePrice = BackendIntegerContract.clampedNonNegative(basePrice)

        guard clampedAdjustedPrice != clampedBasePrice else { return nil }
        guard clampedBasePrice > 0 else { return nil }

        return validated(Double(clampedAdjustedPrice) / Double(clampedBasePrice))
    }

    nonisolated static func distributedPrices(adjustedTotal: Int, basePrices: [Int]) -> [Int] {
        guard !basePrices.isEmpty else { return [] }

        let total = BackendIntegerContract.clampedNonNegative(adjustedTotal)
        let clampedBasePrices = basePrices.map(BackendIntegerContract.clampedNonNegative)
        let baseTotal = clampedBasePrices.reduce(0, +)

        guard baseTotal > 0 else {
            let sharedAmount = total / basePrices.count
            let remainder = total % basePrices.count
            return basePrices.indices.map { index in
                sharedAmount + (index < remainder ? 1 : 0)
            }
        }

        let rawShares = clampedBasePrices.map { basePrice in
            Double(total) * Double(basePrice) / Double(baseTotal)
        }
        var prices = rawShares.map { Int(floor($0)) }
        var remaining = total - prices.reduce(0, +)
        let largestRemainders = rawShares.indices.sorted { lhs, rhs in
            let lhsRemainder = rawShares[lhs] - floor(rawShares[lhs])
            let rhsRemainder = rawShares[rhs] - floor(rawShares[rhs])
            if lhsRemainder == rhsRemainder { return lhs < rhs }
            return lhsRemainder > rhsRemainder
        }

        var index = 0
        while remaining > 0 {
            prices[largestRemainders[index % largestRemainders.count]] += 1
            remaining -= 1
            index += 1
        }

        return prices
    }

    nonisolated static func label(for multiplier: Double?) -> String {
        guard let multiplier else { return "unset" }
        return "x\(format(multiplier))"
    }

    nonisolated static func format(_ multiplier: Double) -> String {
        let formatted = String(format: "%.2f", multiplier)
        var result = formatted
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
