import Foundation

// Shared cadence helpers for both habit rewards and reward prices.
//
// User behaviour we want:
// - if two frequencies mean the same underlying rate, such as `1/day` and
//   `30/month`, they should stabilize at the same speed
// - recent actions should matter more than old ones
// - the history fade should depend on the configured cadence, not on a fixed
//   "last N days" window
enum CadenceDecayPricing {
    nonisolated private static let secondsPerDay = 86_400.0

    // If actions happen exactly on schedule forever, the decayed score tends to
    // this value. Dividing by it keeps "on target" near ratio 1.0.
    nonisolated static let steadyStateUsageNormalization = 1.0 / (1.0 - exp(-1.0))

    // New entities should not instantly trust sparse history. Warm-up is based
    // on target spacing so equivalent rates stabilize equally fast.
    nonisolated private static let warmupSpacingMultiplier = 2.0

    nonisolated static func targetSpacingDays(ratePerDay: Double?) -> Double? {
        guard let ratePerDay, ratePerDay > 0 else { return nil }
        return 1.0 / ratePerDay
    }

    nonisolated static func normalizedUsageRatio(
        eventDates: [Date],
        targetSpacingDays: Double,
        now: Date = Date()
    ) -> Double {
        guard targetSpacingDays > 0 else { return 0 }

        let usageScore = eventDates.reduce(into: 0.0) { partialResult, eventDate in
            let ageSeconds = now.timeIntervalSince(eventDate)
            guard ageSeconds >= 0 else { return }

            let ageDays = ageSeconds / secondsPerDay
            partialResult += exp(-ageDays / targetSpacingDays)
        }

        return usageScore / steadyStateUsageNormalization
    }

    nonisolated static func blendedUsageRatio(
        rawRatio: Double,
        createdAt: Date,
        targetSpacingDays: Double,
        neutralRatio: Double,
        now: Date = Date()
    ) -> Double {
        guard targetSpacingDays > 0 else { return neutralRatio }

        let ageDays = max(0, now.timeIntervalSince(createdAt) / secondsPerDay)
        let warmupDays = targetSpacingDays * warmupSpacingMultiplier
        let weight = min(1.0, ageDays / warmupDays)

        return (weight * rawRatio) + ((1.0 - weight) * neutralRatio)
    }
}

protocol PricingTierOption: CaseIterable, Codable, Equatable, Sendable, Hashable, RawRepresentable {
    var displayName: String { get }
    var shortDescription: String { get }
    var example: String { get }
    var multiplier: Double { get }
    var sortOrder: Int { get }
}

enum PricingTierScaling {
    // React mental model: each tier starts with a neutral base multiplier, then
    // pricing scales by how far that tier sits from `1.0`.
    nonisolated private static let neutralMultiplier = 1.0

    nonisolated static func scaledMultiplier(
        from baseMultiplier: Double,
        influenceMultiplier: Double
    ) -> Double {
        neutralMultiplier + ((baseMultiplier - neutralMultiplier) * influenceMultiplier)
    }
}

enum HabitDifficultyTier: String, PricingTierOption {
    case trivial
    case light
    case medium
    case hard
    case extreme

    nonisolated var displayName: String {
        switch self {
        case .trivial: "Trivial"
        case .light: "Light"
        case .medium: "Medium"
        case .hard: "Hard"
        case .extreme: "Extreme"
        }
    }

    nonisolated var shortDescription: String {
        switch self {
        case .trivial: "Very easy to start and finish. Low effort, low friction."
        case .light: "Easy enough to do most days without much resistance."
        case .medium: "Takes noticeable effort or planning, but feels sustainable."
        case .hard: "You often resist it and need deliberate effort to follow through."
        case .extreme: "A serious stretch task that is rare, draining, or highly uncomfortable."
        }
    }

    nonisolated var example: String {
        switch self {
        case .trivial: "Drink a glass of water."
        case .light: "Message a friend."
        case .medium: "Do 10 pushups."
        case .hard: "Go for a 30 minute run."
        case .extreme: "Deep clean the whole kitchen."
        }
    }

    nonisolated var multiplier: Double {
        switch self {
        case .trivial: PricingTierScaling.scaledMultiplier(from: 0.8, influenceMultiplier: 4.0)
        case .light: PricingTierScaling.scaledMultiplier(from: 0.9, influenceMultiplier: 4.0)
        case .medium: PricingTierScaling.scaledMultiplier(from: 1.0, influenceMultiplier: 4.0)
        case .hard: PricingTierScaling.scaledMultiplier(from: 1.1, influenceMultiplier: 4.0)
        case .extreme: PricingTierScaling.scaledMultiplier(from: 1.25, influenceMultiplier: 4.0)
        }
    }

    nonisolated var sortOrder: Int {
        switch self {
        case .trivial: 0
        case .light: 1
        case .medium: 2
        case .hard: 3
        case .extreme: 4
        }
    }
}

enum RewardDamageTier: String, PricingTierOption {
    case harmless
    case light
    case medium
    case heavy
    case extreme

    nonisolated var displayName: String {
        switch self {
        case .harmless: "Harmless"
        case .light: "Light"
        case .medium: "Medium"
        case .heavy: "Heavy"
        case .extreme: "Extreme"
        }
    }

    nonisolated var shortDescription: String {
        switch self {
        case .harmless: "A small treat with little downside in moderation."
        case .light: "Enjoyable, but easy to overdo if it becomes frequent."
        case .medium: "Noticeably disruptive if used often."
        case .heavy: "Likely to derail energy, focus, or health when repeated."
        case .extreme: "Strongly undermines your goals and needs tight control."
        }
    }

    nonisolated var example: String {
        switch self {
        case .harmless: "One chocolate square."
        case .light: "15 minutes of TikTok."
        case .medium: "Eat a chocolate bar."
        case .heavy: "Skip a workout for scrolling."
        case .extreme: "A full evening lost to doomscrolling."
        }
    }

    nonisolated var multiplier: Double {
        switch self {
        case .harmless: PricingTierScaling.scaledMultiplier(from: 0.8, influenceMultiplier: 4.0)
        case .light: PricingTierScaling.scaledMultiplier(from: 0.9, influenceMultiplier: 4.0)
        case .medium: PricingTierScaling.scaledMultiplier(from: 1.0, influenceMultiplier: 4.0)
        case .heavy: PricingTierScaling.scaledMultiplier(from: 1.1, influenceMultiplier: 4.0)
        case .extreme: PricingTierScaling.scaledMultiplier(from: 1.25, influenceMultiplier: 4.0)
        }
    }

    nonisolated var sortOrder: Int {
        switch self {
        case .harmless: 0
        case .light: 1
        case .medium: 2
        case .heavy: 3
        case .extreme: 4
        }
    }
}

enum SkipConsequenceTier: Int, PricingTierOption {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    nonisolated var displayName: String { "\(rawValue)" }

    nonisolated var shortDescription: String {
        switch self {
        case .one: "Missing this habit is barely noticeable."
        case .two: "Skipping it starts to matter, but recovery is easy."
        case .three: "Missing the target meaningfully hurts momentum."
        case .four: "Letting this slip has clear short-term consequences."
        case .five: "Missing the target quickly creates a serious problem."
        }
    }

    nonisolated var example: String {
        switch self {
        case .one: "Nice to have, but low stakes if missed."
        case .two: "Helpful for consistency, but easy to catch up."
        case .three: "A few missed days noticeably weaken the habit."
        case .four: "Skipping this tends to derail an important area."
        case .five: "Missing this target has strong real-world consequences."
        }
    }

    nonisolated var multiplier: Double {
        switch self {
        case .one: 1.0
        case .two: 1.15
        case .three: 1.3
        case .four: 1.5
        case .five: 1.75
        }
    }

    nonisolated var sortOrder: Int { rawValue - 1 }

    nonisolated static func from(_ rawValue: Int?) -> SkipConsequenceTier? {
        guard let rawValue else { return nil }
        return SkipConsequenceTier(rawValue: rawValue)
    }
}
