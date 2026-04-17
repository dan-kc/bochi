import Foundation

// Deterministic hash used by reward pricing. The output only needs to look
// random to the user; it must still be exactly repeatable so iOS and web show
// the same price for the same habit in the same time bucket.
//
// Caseless enum = namespace (like a TS module that only exports functions).
// You can't instantiate it — it just groups related static functions.
enum DeterministicHash {

    // Uses UInt32 math so the port behaves like JavaScript's 32-bit integer
    // operations. That parity matters more here than using more "native" Swift.
    static func hash(_ input: String) -> Double {
        var h1: UInt32 = 0xdeadbeef
        var h2: UInt32 = 0x41c6ce57

        for scalar in input.unicodeScalars {
            let char = UInt32(scalar.value)
            h1 = (h1 ^ char) &* 2654435761
            h2 = (h2 ^ char) &* 1597334677
        }

        h1 = (h1 ^ (h1 >> 16)) &* 2246822507
        h1 = (h1 ^ (h1 >> 13)) &* 3266489909
        h1 ^= h1 >> 16

        h2 = (h2 ^ (h2 >> 16)) &* 2246822507
        h2 = (h2 ^ (h2 >> 13)) &* 3266489909
        h2 ^= h2 >> 16

        let combined = h1 ^ h2
        return Double(combined) / Double(0xFFFFFFFF)
    }
}
