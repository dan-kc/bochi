import Foundation

// The Rust backend serializes UUIDs in lowercase, while Swift's
// `UUID().uuidString` uses uppercase hex. The app treats ids as plain strings,
// so one logical record can look like two different rows unless we canonicalize
// them before storing, comparing, or syncing.
enum CanonicalRecordID {
    static func normalize(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalize(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        return normalize(rawValue)
    }
}
