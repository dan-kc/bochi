import Foundation

// DifficultyRanker implements the binary search comparison algorithm for
// placing a new habit in the difficulty ordering.
//
// In the React Native frontend (DifficultyRanker.tsx), this logic was mixed
// into the UI component using useState/useEffect. Here we separate it into a
// pure struct (Session) that the view can drive — this makes unit testing
// trivial without needing UI tests.
//
// The algorithm: given habits sorted hardest→easiest by difficultyRank,
// binary search to find where the new habit fits by asking the user
// "is your habit harder or easier than X?", then use FractionalIndex
// to generate a key between the neighbors.
enum DifficultyRanker {

    // Represents the state of a ranking session.
    //
    // In React, this was multiple useState hooks (low, high, state, comparisonCount).
    // In Swift, we bundle them into a single struct with mutating methods.
    // `mutating` means the method modifies `self` — like reassigning state in
    // a useReducer dispatch. Required because Swift structs are value types.
    struct Session {
        let habitName: String
        let rankedHabits: [Habit]  // sorted hardest (highest rank) → easiest (lowest rank)
        var low: Int
        var high: Int
        var comparisonCount: Int = 0

        // True when the binary search has narrowed down to a single position
        var isComplete: Bool { low >= high }

        // The habit currently being compared against, or nil if complete
        var currentComparison: Habit? {
            isComplete ? nil : rankedHabits[mid]
        }

        // Current midpoint index — like `const mid = Math.floor((low + high) / 2)`
        var mid: Int { (low + high) / 2 }

        // How many comparisons we expect — ceil(log2(n+1))
        var estimatedComparisons: Int {
            rankedHabits.isEmpty ? 0 : Int(ceil(log2(Double(rankedHabits.count + 1))))
        }

        // User says new habit is HARDER than the comparison habit.
        // Narrows search to the upper (harder) half.
        // In the React version: `setHigh(mid)`
        mutating func chooseHarder() {
            high = mid
            comparisonCount += 1
        }

        // User says new habit is EASIER than the comparison habit.
        // Narrows search to the lower (easier) half.
        // In the React version: `setLow(mid + 1)`
        mutating func chooseEasier() {
            low = mid + 1
            comparisonCount += 1
        }

        // Generates the fractional index key for the determined position.
        // Call this after isComplete is true.
        //
        // The key is generated between the neighbors at the insertion point:
        //   - harderRank: the rank of the habit just harder (lower index, higher rank)
        //   - easierRank: the rank of the habit just easier (higher index, lower rank)
        func generateRank() -> String {
            // rankedHabits is sorted hardest→easiest, so:
            //   index 0 = hardest, index last = easiest
            //   low is the insertion point
            //
            // The habit at low-1 is harder, the habit at low is easier
            let harderRank = low > 0 ? rankedHabits[low - 1].difficultyRank : nil
            let easierRank = low < rankedHabits.count ? rankedHabits[low].difficultyRank : nil

            // FractionalIndex generates a key between easier and harder.
            // before = easier (lower key), after = harder (higher key)
            return FractionalIndex.generateKeyBetween(before: easierRank, after: harderRank) ?? "m"
        }
    }

    // Creates a new ranking session for the given habit name against existing
    // ranked habits (which must be sorted hardest→easiest).
    static func makeSession(habitName: String, rankedHabits: [Habit]) -> Session {
        Session(
            habitName: habitName,
            rankedHabits: rankedHabits,
            low: 0,
            high: rankedHabits.count
        )
    }
}
