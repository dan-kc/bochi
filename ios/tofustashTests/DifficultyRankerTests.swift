import Foundation
import Testing
@testable import tofustash

struct DifficultyRankerTests {

    // Helper to create a habit with a specific difficulty rank
    private func makeHabit(name: String, rank: String?) -> Habit {
        Habit(
            id: UUID().uuidString,
            name: name,
            description: "",
            createdAt: Date(),
            updatedAt: Date(),
            deletedAt: nil,
            frequency: nil,
            difficultyRank: rank
        )
    }

    // MARK: - Session creation

    // Behaviour: When a user creates their very first habit, there are no other habits
    // to compare against, so the difficulty ranking step is skipped entirely.
    @Test func sessionWithNoRankedHabitsIsImmediatelyComplete() {
        let session = DifficultyRanker.makeSession(
            habitName: "New Habit",
            rankedHabits: []
        )

        #expect(session.isComplete)
    }

    // Behaviour: The first habit ever ranked gets a middle position, leaving room
    // for future habits to be ranked above or below it.
    @Test func rankFirstHabitReturnsMiddleKey() {
        let session = DifficultyRanker.makeSession(
            habitName: "New Habit",
            rankedHabits: []
        )

        let rank = session.generateRank()
        #expect(rank == "m")
    }

    // MARK: - Binary search

    // Behaviour: When only one habit exists, the user only needs to answer one
    // comparison ("Is this harder or easier than X?") to place the new habit.
    @Test func sessionWithOneHabitNeedsOneComparison() {
        let existing = makeHabit(name: "Existing", rank: "m")
        var session = DifficultyRanker.makeSession(
            habitName: "New",
            rankedHabits: [existing]
        )

        #expect(!session.isComplete)
        #expect(session.currentComparison?.name == "Existing")

        // Choose harder → new habit is harder than existing
        session.chooseHarder()
        #expect(session.isComplete)
    }

    // Behaviour: When a user says their new habit is harder than all existing habits,
    // it gets placed at the top of the difficulty list.
    @Test func rankHarderThanAllReturnsHigherKey() {
        let existing = makeHabit(name: "Existing", rank: "m")
        var session = DifficultyRanker.makeSession(
            habitName: "New",
            rankedHabits: [existing] // sorted hardest→easiest
        )

        session.chooseHarder()
        let rank = session.generateRank()

        // Should be higher than "m" (harder than all existing)
        #expect(rank > "m")
    }

    // Behaviour: When a user says their new habit is easier than all existing habits,
    // it gets placed at the bottom of the difficulty list.
    @Test func rankEasierThanAllReturnsLowerKey() {
        let existing = makeHabit(name: "Existing", rank: "m")
        var session = DifficultyRanker.makeSession(
            habitName: "New",
            rankedHabits: [existing]
        )

        session.chooseEasier()
        let rank = session.generateRank()

        // Should be lower than "m" (easier than all existing)
        #expect(rank < "m")
    }

    // Behaviour: When a user ranks a habit between two existing habits (harder than
    // one, easier than the other), it gets placed correctly between them.
    @Test func rankBetweenTwoHabitsReturnsMidpointKey() {
        let hard = makeHabit(name: "Hard", rank: "t")
        let easy = makeHabit(name: "Easy", rank: "f")
        var session = DifficultyRanker.makeSession(
            habitName: "Medium",
            rankedHabits: [hard, easy] // sorted hardest→easiest
        )

        // mid = (0+2)/2 = 1, compares with easy ("f")
        // Choose harder → new habit is harder than easy
        session.chooseHarder()

        // Now low=0, high=1, mid=0, compares with hard ("t")
        // Choose easier → new habit is easier than hard
        session.chooseEasier()

        #expect(session.isComplete)
        let rank = session.generateRank()

        // Should be between "f" and "t"
        #expect(rank > "f")
        #expect(rank < "t")
    }

    // Behaviour: Even with many habits (8), the ranking process converges efficiently
    // via binary search — the user answers at most ~4 questions, not 8.
    @Test func binarySearchConvergesCorrectly() {
        // Create 8 habits with ordered ranks
        let ranks = ["d", "f", "h", "j", "m", "p", "r", "t"]
        let habits = ranks.map { makeHabit(name: "Habit-\($0)", rank: $0) }

        var session = DifficultyRanker.makeSession(
            habitName: "New",
            rankedHabits: habits // hardest→easiest already sorted descending
                .sorted { ($0.difficultyRank ?? "") > ($1.difficultyRank ?? "") }
        )

        // Keep choosing "easier" — should converge to inserting after the easiest
        var steps = 0
        while !session.isComplete {
            session.chooseEasier()
            steps += 1
            // Safety: binary search on 8 items should take at most 4 steps
            #expect(steps <= 4, "Binary search should converge in log2(8) = 3-4 steps")
        }

        let rank = session.generateRank()
        // Should be less than the easiest rank ("d")
        #expect(rank < "d")
    }

    // Behaviour: The app can tell the user approximately how many comparisons
    // they'll need to make, so the ranking process feels predictable.
    @Test func estimatedComparisonsIsCorrect() {
        let habits = (0..<8).map { makeHabit(name: "H\($0)", rank: "m") }
        let session = DifficultyRanker.makeSession(
            habitName: "New",
            rankedHabits: habits
        )

        // ceil(log2(8+1)) = ceil(3.17) = 4
        #expect(session.estimatedComparisons == 4)
    }

    // MARK: - Unset button visibility

    // Behaviour: When a habit already has a difficulty rank and the user opens the
    // ranker, they should see an "Unset" button to clear it.
    @Test func shouldShowUnsetButton_whenRankIsSet_returnsTrue() {
        #expect(DifficultyRankerView.shouldShowUnsetButton(currentDifficultyRank: "m") == true)
    }

    // Behaviour: When difficulty isn't set yet, there's nothing to unset,
    // so the button is hidden.
    @Test func shouldShowUnsetButton_whenRankIsNil_returnsFalse() {
        #expect(DifficultyRankerView.shouldShowUnsetButton(currentDifficultyRank: nil) == false)
    }

}
