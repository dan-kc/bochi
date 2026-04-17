import Foundation

// DifficultyRanker drives the "harder or easier than X?" flow that users see
// when setting a habit's difficulty.
//
// In the React Native frontend (DifficultyRanker.tsx), this logic was mixed
// into the UI component using useState/useEffect. Here we separate it into a
// pure struct (Session) that the view can drive — this makes unit testing
// trivial without needing UI tests.
//
// The algorithm is binary search over the already-ranked habits. That keeps the
// number of user comparisons small even when the list grows.
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

        // Once low == high, the app knows exactly where the new habit belongs.
        var isComplete: Bool { low >= high }

        // The current prompt shown to the user in the ranker sheet.
        var currentComparison: Habit? {
            isComplete ? nil : rankedHabits[mid]
        }

        // Midpoint choice for the next comparison.
        var mid: Int { (low + high) / 2 }

        // Used to show progress text like "about 4 comparisons left".
        var estimatedComparisons: Int {
            rankedHabits.isEmpty ? 0 : Int(ceil(log2(Double(rankedHabits.count + 1))))
        }

        // User chose "Harder", so the insertion point must be above the current
        // comparison in the ordered list.
        mutating func chooseHarder() {
            high = mid
            comparisonCount += 1
        }

        // User chose "Easier", so the insertion point moves below the current
        // comparison.
        mutating func chooseEasier() {
            low = mid + 1
            comparisonCount += 1
        }

        // Converts the final insertion point into a stable sort key so later
        // sessions can reconstruct the same difficulty order without rerunning
        // the comparison flow.
        func generateRank() -> String {
            let harderRank = low > 0 ? rankedHabits[low - 1].difficultyRank : nil
            let easierRank = low < rankedHabits.count ? rankedHabits[low].difficultyRank : nil

            return FractionalIndex.generateKeyBetween(before: easierRank, after: harderRank) ?? "m"
        }
    }

    // Starts a fresh ranking flow for one habit.
    static func makeSession(habitName: String, rankedHabits: [Habit]) -> Session {
        Session(
            habitName: habitName,
            rankedHabits: rankedHabits,
            low: 0,
            high: rankedHabits.count
        )
    }
}
