import Foundation
import Testing
@testable import tofustash

struct FractionalIndexTests {

    // MARK: - Edge Cases (nil inputs)

    @Test func generateKeyBetweenNilNilReturnsM() {
        let key = FractionalIndex.generateKeyBetween(before: nil, after: nil)
        #expect(key == "m")
    }

    @Test func generateKeyBetweenNilAndKeyReturnsLowerKey() {
        let key = FractionalIndex.generateKeyBetween(before: nil, after: "m")!
        #expect(key < "m")
    }

    @Test func generateKeyBetweenKeyAndNilReturnsHigherKey() {
        let key = FractionalIndex.generateKeyBetween(before: "m", after: nil)!
        #expect(key > "m")
    }

    // MARK: - Between two keys

    @Test func generateKeyBetweenTwoKeysReturnsMidpoint() {
        let key = FractionalIndex.generateKeyBetween(before: "a", after: "z")!
        #expect(key > "a")
        #expect(key < "z")
    }

    @Test func generateKeyBetweenAdjacentKeysGoesDeeper() {
        // Between "a" and "b" there's no single-character midpoint, so
        // the algorithm must go deeper (append characters).
        let key = FractionalIndex.generateKeyBetween(before: "a", after: "b")!
        #expect(key > "a")
        #expect(key < "b")
        #expect(key.count > 1)
    }

    // MARK: - Ordering guarantees

    @Test func generateKeyBetweenMaintainsOrdering() {
        // Generate 20 keys by always inserting after the last one.
        var keys: [String] = []
        var previous: String? = nil

        for _ in 0..<20 {
            let key = FractionalIndex.generateKeyBetween(before: previous, after: nil)!
            keys.append(key)
            previous = key
        }

        for i in 1..<keys.count {
            #expect(keys[i] > keys[i - 1], "Key \(keys[i]) should be > \(keys[i - 1])")
        }

        let sorted = keys.sorted()
        #expect(keys == sorted)
    }

    @Test func generateKeyBetweenCanInsertBetweenAdjacentKeys() {
        let a = FractionalIndex.generateKeyBetween(before: nil, after: nil)! // "m"
        let b = FractionalIndex.generateKeyBetween(before: a, after: nil)!

        var lower = a
        for _ in 0..<5 {
            let mid = FractionalIndex.generateKeyBetween(before: lower, after: b)!
            #expect(mid > lower)
            #expect(mid < b)
            lower = mid
        }
    }

    // MARK: - Invalid input

    @Test func generateKeyBetweenInvalidOrderReturnsNil() {
        let key1 = FractionalIndex.generateKeyBetween(before: "z", after: "a")
        #expect(key1 == nil)

        let key2 = FractionalIndex.generateKeyBetween(before: "m", after: "m")
        #expect(key2 == nil)
    }
}
