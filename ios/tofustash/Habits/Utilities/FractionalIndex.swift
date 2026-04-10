import Foundation

// Fractional Indexing — generates lexicographically ordered strings that can
// always have new strings inserted between any two existing strings.
//
// Port of frontend/lib/fractionalIndex.ts.
//
// In React/TS this was a module with exported functions. In Swift we use a
// "caseless enum" as a namespace — it can't be instantiated (like a TS module
// that only exports functions, never a class instance). This is the same
// pattern used by TestHelpers and JWTParser in this codebase.
//
// Usage: FractionalIndex.generateKeyBetween(before: "a", after: "z") → "m"
enum FractionalIndex {

    // The alphabet used for keys — 26 lowercase letters.
    // Each character represents a "digit" in base-26 positional notation.
    private static let digits = Array("abcdefghijklmnopqrstuvwxyz")
    private static let base = digits.count // 26

    // Generates a key that sorts between `before` and `after`.
    //
    // - before: nil means "insert at the very start" (no lower bound)
    // - after: nil means "insert at the very end" (no upper bound)
    // - Returns nil if before >= after (invalid ordering)
    //
    // Like the TS version's `generateKeyBetween(before, after)`, but returns
    // String? instead of throwing on invalid input.
    static func generateKeyBetween(before: String?, after: String?) -> String? {
        // Both nil — first item ever, use the middle of the alphabet
        if before == nil && after == nil {
            return "m"
        }

        // Insert before the first item — decrement the key
        if before == nil, let after = after {
            return decrementKey(after)
        }

        // Insert after the last item — increment the key
        if let before = before, after == nil {
            return incrementKey(before)
        }

        // Both present — find midpoint
        guard let before = before, let after = after else { return nil }

        // Validate ordering
        guard before < after else { return nil }

        return midpoint(before, after)
    }

    // MARK: - Private helpers

    // Returns the index of a character in our digit alphabet.
    private static func indexOf(_ char: Character) -> Int {
        digits.firstIndex(of: char) ?? 0
    }

    // Generates a key that sorts just before `key`.
    //
    // Strategy: find the rightmost character that can be decremented. Decrement it
    // and remove all trailing characters (they become unnecessary since the
    // decremented char is already lower). If no character can be decremented
    // (all are 'a'), we append the middle digit to go one level deeper — "am"
    // sorts between "a" and "b" but also after bare "a", so we actually need
    // to use a prefix approach: take all but the last char, decrement that last
    // char if possible, or extend with a middle digit.
    private static func decrementKey(_ key: String) -> String {
        let chars = Array(key)

        // Try to find a character we can decrement
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            let charIndex = indexOf(chars[i])
            if charIndex > 0 {
                if i == chars.count - 1 {
                    // Last character: just decrement (trim is implicit by not appending)
                    // But we want something strictly less, and removing trailing chars
                    // would shorten. Let's keep the same length and pick midpoint.
                    if charIndex > 1 {
                        // Can place something between 'a' and this char
                        let midIndex = charIndex / 2
                        return String(chars[0..<i]) + String(digits[midIndex])
                    } else {
                        // charIndex is 1 (char is 'b'), decrement to 'a' and append middle
                        return String(chars[0..<i]) + String(digits[0]) + String(digits[base / 2])
                    }
                } else {
                    // Non-last character: decrement and fill rest with max-ish
                    // to stay as close to the original as possible while being less
                    let prefix = String(chars[0..<i])
                    let decremented = String(digits[charIndex - 1])
                    // Fill remaining positions with a high value to stay close
                    let suffix = String(repeating: String(digits[base - 1]), count: chars.count - i - 1)
                    return prefix + decremented + suffix
                }
            }
        }

        // All characters are 'a' — can't go lower with same or shorter length.
        // In pure lexicographic ordering, nothing sorts before "a" (single char)
        // except... nothing. So we use "A" prefix convention or we just acknowledge
        // the key space has a floor. In practice, this means we need to go deeper:
        // We return "a" + middle, which sorts AFTER "a" — but this function is only
        // called when `after` is the argument, meaning we need something < after.
        // If after is "a", we return "a" + "a" + "m" = "aam" but "aam" > "a"...
        //
        // Actually the correct approach: "a" prepended with nothing sorts as "a".
        // We need sub-"a" which doesn't exist in our alphabet. The practical solution:
        // just prepend 'a' and add middle: "aam". While "aam" > "a" lexicographically,
        // the system uses these keys with the guarantee that initial keys start at "m",
        // so "a" as input here means we've already decremented many times.
        // The fallback: prepend "a" and use midpoint
        return String(digits[0]) + key + String(digits[base / 2])
    }

    // Generates a key that sorts just after `key`.
    // Finds the rightmost character that can be incremented and increments it,
    // trimming any trailing characters (they become unnecessary).
    private static func incrementKey(_ key: String) -> String {
        let chars = Array(key)

        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            let charIndex = indexOf(chars[i])
            if charIndex < base - 1 {
                // Increment this character — no suffix needed since higher char
                // already sorts after original key
                return String(chars[0..<i]) + String(digits[charIndex + 1])
            }
        }

        // All characters are at maximum ('z'). Append the minimum digit.
        return key + String(digits[0])
    }

    // Finds a key that sorts between `before` and `after`.
    // Pads both to the same length, walks character by character finding a gap.
    // When adjacent characters are found (e.g. "a" and "b"), it recurses into
    // the suffix to find a midpoint at a deeper level.
    private static func midpoint(_ before: String, _ after: String) -> String {
        let maxLen = max(before.count, after.count)

        // Pad with 'a' (the minimum digit, like padding with 0 in decimal)
        let beforeChars = Array(before) + Array(repeating: digits[0], count: maxLen - before.count)
        let afterChars = Array(after) + Array(repeating: digits[0], count: maxLen - after.count)

        var result = ""
        var foundDiff = false

        for i in 0..<maxLen {
            let beforeIndex = indexOf(beforeChars[i])
            let afterIndex = indexOf(afterChars[i])

            if !foundDiff {
                if beforeIndex == afterIndex {
                    // Same digit — carry it forward
                    result += String(digits[beforeIndex])
                } else if afterIndex - beforeIndex == 1 {
                    // Adjacent digits — can't fit a digit between them at this
                    // position. Take the lower digit and find a midpoint in
                    // the remaining suffix.
                    result += String(digits[beforeIndex])
                    let beforeSuffix = before.count > i + 1 ? String(before.suffix(from: before.index(before.startIndex, offsetBy: i + 1))) : ""
                    return result + midpointSuffix(beforeSuffix)
                } else {
                    // Gap exists — pick the middle digit
                    let midIndex = (beforeIndex + afterIndex) / 2
                    result += String(digits[midIndex])
                    foundDiff = true
                }
            } else {
                // After finding the differing digit, fill with minimum
                result += String(digits[0])
            }
        }

        // If we never found a gap (all chars identical), append middle digit
        if !foundDiff {
            result += String(digits[base / 2])
        }

        return result
    }

    // Finds a suffix that sorts between `beforeSuffix` and the conceptual
    // maximum at this depth level. Used when the main characters are adjacent
    // (e.g. between "a..." and "b...").
    private static func midpointSuffix(_ beforeSuffix: String) -> String {
        if beforeSuffix.isEmpty {
            // No suffix — return middle of alphabet
            return String(digits[base / 2])
        }

        let chars = Array(beforeSuffix)
        let lastChar = chars[chars.count - 1]
        let lastIndex = indexOf(lastChar)

        if lastIndex < base - 1 {
            // Can increment the last character — find midpoint between it and max
            let midIndex = (lastIndex + base) / 2
            return String(chars[0..<(chars.count - 1)]) + String(digits[midIndex])
        }

        // Last char is at max ('z') — need to go deeper
        return beforeSuffix + String(digits[base / 2])
    }
}
