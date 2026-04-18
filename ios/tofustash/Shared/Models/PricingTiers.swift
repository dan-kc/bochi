import Foundation

protocol PricingTierOption: CaseIterable, Codable, Equatable, Sendable, Hashable, RawRepresentable<String> {
    var displayName: String { get }
    var shortDescription: String { get }
    var example: String { get }
    var multiplier: Double { get }
    var sortOrder: Int { get }
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
        case .trivial: 0.8
        case .light: 0.9
        case .medium: 1.0
        case .hard: 1.1
        case .extreme: 1.25
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
        case .harmless: 0.8
        case .light: 0.9
        case .medium: 1.0
        case .heavy: 1.1
        case .extreme: 1.25
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
