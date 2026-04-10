import Foundation

// Caseless enum used as a namespace — can't be instantiated (like a TS namespace, or a Go package with only exported vars)
enum AppConfiguration {
    // `static` — belongs to the type, not an instance (like TS static class members)
    // `!` — force-unwrap the Optional. Crashes if nil at runtime (like Rust's .unwrap()). Safe here because the string is a valid URL literal.
    static let apiBaseURL = URL(string: "http://localhost:8501")!
}
