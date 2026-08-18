import Foundation

enum PriceDeltaSupport {
    nonisolated static func percent(currentPrice: Int, basePrice: Int) -> Int? {
        guard basePrice > 0 else { return nil }

        let percent = Int(((Double(currentPrice - basePrice) / Double(basePrice)) * 100).rounded())
        return percent == 0 ? nil : percent
    }

    nonisolated static func label(for percent: Int?) -> String? {
        guard let percent, percent != 0 else { return nil }
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }
}
