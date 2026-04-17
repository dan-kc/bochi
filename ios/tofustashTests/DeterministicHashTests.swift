import Testing
@testable import tofustash

// Tests for the deterministic hash function that produces the random multiplier
// in reward calculations. This hash must produce bit-identical output to the
// JavaScript version (MurmurHash3-inspired) so rewards are consistent across
// platforms.
struct DeterministicHashTests {

    // -- Cross-platform parity: these expected values were computed by running
    //    the JavaScript deterministicHash function on the same inputs.

    // Behaviour: A user looking at the same habit on web and iOS should see the same reward price in the same time bucket.
    @Test("Produces the same value as the JS implementation for a typical seed")
    func parityTypicalSeed() {
        let result = DeterministicHash.hash("test-habit-1-12345")
        #expect(abs(result - 0.47584227623321168) < 1e-10)
    }

    // Behaviour: Price parity holds for one concrete habit/time-bucket pair, not just a synthetic sample.
    @Test("Parity: habit-1 with time bucket 12345")
    func parityHabit1() {
        let result = DeterministicHash.hash("habit-1-12345")
        #expect(abs(result - 0.53469908925115572) < 1e-10)
    }

    // Behaviour: Different habits still stay in sync across platforms for the same moment in time.
    @Test("Parity: habit-2 with time bucket 12345")
    func parityHabit2() {
        let result = DeterministicHash.hash("habit-2-12345")
        #expect(abs(result - 0.17199489012639851) < 1e-10)
    }

    // Behaviour: When the 30-minute bucket changes, iOS matches the new web price instead of holding the old one.
    @Test("Parity: habit-1 with time bucket 12346")
    func parityDifferentBucket() {
        let result = DeterministicHash.hash("habit-1-12346")
        #expect(abs(result - 0.64405091890228239) < 1e-10)
    }

    // Behaviour: Even edge-case seeds still produce the same cross-platform price component.
    @Test("Parity: empty string")
    func parityEmptyString() {
        let result = DeterministicHash.hash("")
        #expect(abs(result - 0.27723839256848171) < 1e-10)
    }

    // Behaviour: Very short habit identifiers still yield stable prices across platforms.
    @Test("Parity: single character")
    func paritySingleChar() {
        let result = DeterministicHash.hash("a")
        #expect(abs(result - 0.45511451653556773) < 1e-10)
    }

    // Behaviour: Normal multi-word seeds stay aligned too, covering more realistic generated strings.
    @Test("Parity: multi-word string")
    func parityMultiWord() {
        let result = DeterministicHash.hash("hello world")
        #expect(abs(result - 0.64975885177258375) < 1e-10)
    }

    // -- Behavioural properties

    // Behaviour: Revisiting the same habit in the same bucket should not make the visible price drift.
    @Test("Same input always produces the same output")
    func deterministic() {
        let a = DeterministicHash.hash("some-input")
        let b = DeterministicHash.hash("some-input")
        #expect(a == b)
    }

    // Behaviour: The random price adjustment stays within the intended +/-10% band.
    @Test("Output is always in [0, 1]")
    func outputRange() {
        // Spot-check a variety of inputs
        let inputs = ["", "a", "abc", "test-habit-1-99999", "zzzzzzzzz", "0"]
        for input in inputs {
            let result = DeterministicHash.hash(input)
            #expect(result >= 0, "Hash of \"\(input)\" was below 0: \(result)")
            #expect(result <= 1, "Hash of \"\(input)\" was above 1: \(result)")
        }
    }

    // Behaviour: Different habits should usually not show the exact same random adjustment.
    @Test("Different inputs produce different outputs")
    func differentInputs() {
        let a = DeterministicHash.hash("input-a")
        let b = DeterministicHash.hash("input-b")
        #expect(a != b)
    }
}
