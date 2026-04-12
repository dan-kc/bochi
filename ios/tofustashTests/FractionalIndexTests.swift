import Foundation
import Testing
@testable import tofustash

struct FractionalIndexTests {

    // MARK: - Edge Cases (nil inputs)

    // Behaviour: When the user creates the very first item in a list (nothing before
    // or after), it gets a default middle position.
    @Test func generateKeyBetweenNilNilReturnsM() {
        let key = FractionalIndex.generateKeyBetween(before: nil, after: nil)
        #expect(key == "m")
    }

    // Behaviour: When the user moves an item to the beginning of a list (before
    // the first item), it gets a sort key lower than the first item.
    @Test func generateKeyBetweenNilAndKeyReturnsLowerKey() {
        let key = FractionalIndex.generateKeyBetween(before: nil, after: "m")!
        #expect(key < "m")
    }

    // Behaviour: When the user moves an item to the end of a list (after the last
    // item), it gets a sort key higher than the last item.
    @Test func generateKeyBetweenKeyAndNilReturnsHigherKey() {
        let key = FractionalIndex.generateKeyBetween(before: "m", after: nil)!
        #expect(key > "m")
    }

    // MARK: - Between two keys

    // Behaviour: When the user drags an item between two others, it gets a sort
    // key that falls between them, preserving the visual order.
    @Test func generateKeyBetweenTwoKeysReturnsMidpoint() {
        let key = FractionalIndex.generateKeyBetween(before: "a", after: "z")!
        #expect(key > "a")
        #expect(key < "z")
    }

    // Behaviour: When items are very close together in sort order (adjacent keys),
    // the system can still insert between them by using longer keys.
    @Test func generateKeyBetweenAdjacentKeysGoesDeeper() {
        // Between "a" and "b" there's no single-character midpoint, so
        // the algorithm must go deeper (append characters).
        let key = FractionalIndex.generateKeyBetween(before: "a", after: "b")!
        #expect(key > "a")
        #expect(key < "b")
        #expect(key.count > 1)
    }

    // MARK: - Ordering guarantees

    // Behaviour: When the user adds many items sequentially, the sort order is always
    // maintained — items never "jump" out of position.
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

    // Behaviour: When the user repeatedly inserts items between the same two items
    // (e.g. keeps adding habits between positions 2 and 3), the ordering remains correct.
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

    // Behaviour: If sort keys are passed in the wrong order (a bug), the function
    // returns nil instead of producing a corrupt key. This is a safety net.
    @Test func generateKeyBetweenInvalidOrderReturnsNil() {
        let key1 = FractionalIndex.generateKeyBetween(before: "z", after: "a")
        #expect(key1 == nil)

        let key2 = FractionalIndex.generateKeyBetween(before: "m", after: "m")
        #expect(key2 == nil)
    }
}
