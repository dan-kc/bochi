import Foundation

// RecordID wraps every persisted/synced entity identifier in one type so the
// canonicalization rule lives at the boundary instead of being repeated in
// every store. This is the Swift equivalent of replacing a loose `string`
// alias in TypeScript with a tiny value object that enforces an invariant.
//
// Why this exists:
// - Swift's `UUID().uuidString` emits uppercase hex.
// - The Rust backend serializes UUIDs in lowercase.
// - If the app treats ids as plain case-sensitive strings, one logical record
//   can appear twice after sync: once from the local create and once from the
//   server echo.
//
// User behaviour protected by this type:
// creating a recurringTask/reward locally and then receiving the same row back from
// sync must still render as one item, not a duplicate.
nonisolated struct RecordID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // Convenience for new local records. This keeps ID generation and
    // canonicalization coupled so callers do not have to remember both steps.
    init() {
        self.init(rawValue: UUID().uuidString)
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        rawValue
    }
}
