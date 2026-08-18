import Foundation

struct PremiumProductDisclosure: Equatable {
    let lengthText: String
    let priceUnitText: String
    let renewalText: String?
}

enum PremiumProductKind: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        case .lifetime:
            return "Lifetime"
        }
    }

    var fallbackProductID: String {
        switch self {
        case .monthly:
            return "monthly.membership"
        case .yearly:
            return "annual.membership"
        case .lifetime:
            return "lifetime.membership"
        }
    }

    var environmentKey: String {
        "BOCHI_PREMIUM_\(rawValue.uppercased())_PRODUCT_ID"
    }

    var disclosure: PremiumProductDisclosure {
        switch self {
        case .monthly:
            return PremiumProductDisclosure(
                lengthText: "1 month auto-renewable subscription",
                priceUnitText: "per month",
                renewalText: "Renews automatically until canceled."
            )
        case .yearly:
            return PremiumProductDisclosure(
                lengthText: "1 year auto-renewable subscription",
                priceUnitText: "per year",
                renewalText: "Renews automatically until canceled."
            )
        case .lifetime:
            return PremiumProductDisclosure(
                lengthText: "Lifetime access",
                priceUnitText: "one-time purchase",
                renewalText: nil
            )
        }
    }
}

enum PremiumProductConfiguration {
    static func productID(
        for kind: PremiumProductKind,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let override = environment[kind.environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Behaviour: App Store Connect product ids are final product wiring, so
        // local schemes can override them until the real ids are known.
        if let override, !override.isEmpty {
            return override
        }

        return kind.fallbackProductID
    }

    static func productIDs(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        PremiumProductKind.allCases.map { productID(for: $0, environment: environment) }
    }

    static func productKind(
        for productID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PremiumProductKind? {
        PremiumProductKind.allCases.first { kind in
            Self.productID(for: kind, environment: environment) == productID
        }
    }

    static func disclosure(
        for productID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PremiumProductDisclosure? {
        productKind(for: productID, environment: environment)?.disclosure
    }
}
