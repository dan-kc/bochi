import Foundation

// Deterministic hash function that produces values in [0, 1].
// Uses a MurmurHash3-inspired algorithm with good avalanche properties.
//
// This is a direct port of the JavaScript version in
// frontend/lib/rewardCalculation.ts. It MUST produce bit-identical output
// for the same input string so rewards are consistent across platforms.
//
// Caseless enum = namespace (like a TS module that only exports functions).
// You can't instantiate it — it just groups related static functions.
enum DeterministicHash {

    // Hashes a string to a Double in [0, 1].
    //
    // Uses UInt32 throughout to match JavaScript's 32-bit integer semantics:
    //   - `&*` = wrapping multiplication (matches JS `Math.imul`)
    //   - `>>` on UInt32 = unsigned right shift (matches JS `>>>`)
    //   - `^` = XOR (same in both languages)
    //
    // Iterates over Unicode scalars (not characters) to match JS `charCodeAt`,
    // which returns UTF-16 code units. For ASCII/BMP characters (the typical
    // case for habit IDs + time buckets), scalar.value == charCodeAt value.
    static func hash(_ input: String) -> Double {
        var h1: UInt32 = 0xdeadbeef
        var h2: UInt32 = 0x41c6ce57

        for scalar in input.unicodeScalars {
            let char = UInt32(scalar.value)
            h1 = (h1 ^ char) &* 2654435761
            h2 = (h2 ^ char) &* 1597334677
        }

        // Final mixing for avalanche effect — ensures small input changes
        // propagate to all bits of the output. Each step XORs a shifted copy
        // back into itself, then multiplies by a large prime.
        h1 = (h1 ^ (h1 >> 16)) &* 2246822507
        h1 = (h1 ^ (h1 >> 13)) &* 3266489909
        h1 ^= h1 >> 16

        h2 = (h2 ^ (h2 >> 16)) &* 2246822507
        h2 = (h2 ^ (h2 >> 13)) &* 3266489909
        h2 ^= h2 >> 16

        // Combine both hashes via XOR and normalize to [0, 1]
        let combined = h1 ^ h2
        return Double(combined) / Double(0xFFFFFFFF)
    }
}
