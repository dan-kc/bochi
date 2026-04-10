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

    @Test func sessionWithNoRankedHabitsIsImmediatelyComplete() {
        // When there are no existing ranked habits, the session completes
        // immediately — like the React effect that fires when existingHabits.length === 0
        let session = DifficultyRanker.makeSession(
            habitName: "New Habit",
            rankedHabits: []
        )

        #expect(session.isComplete)
    }

    @Test func rankFirstHabitReturnsMiddleKey() {
        let session = DifficultyRanker.makeSession(
            habitName: "New Habit",
            rankedHabits: []
        )

        let rank = session.generateRank()
        #expect(rank == "m")
    }

    // MARK: - Binary search

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

    @Test func estimatedComparisonsIsCorrect() {
        let habits = (0..<8).map { makeHabit(name: "H\($0)", rank: "m") }
        let session = DifficultyRanker.makeSession(
            habitName: "New",
            rankedHabits: habits
        )

        // ceil(log2(8+1)) = ceil(3.17) = 4
        #expect(session.estimatedComparisons == 4)
    }

    @Test func estimatedComparisonsForEmptyIsZero() {
        let session = DifficultyRanker.makeSession(
            habitName: "New",
            rankedHabits: []
        )
        #expect(session.estimatedComparisons == 0)
    }
}
