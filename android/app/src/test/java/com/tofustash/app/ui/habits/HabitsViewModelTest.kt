package com.tofustash.app.ui.habits

import com.tofustash.app.data.local.entity.HabitEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HabitsViewModelTest {

    private fun makeHabit(
        id: String = "h1",
        name: String = "Test",
        price: Int = 500,
        previousPrice: Int = 400,
        difficultyRank: String? = null,
        frequency: Double? = null,
        createdAt: String = "2024-01-01T00:00:00",
    ) = HabitWithPrice(
        habit = HabitEntity(
            id = id, userId = "u1", name = name, description = "",
            createdAt = createdAt, updatedAt = createdAt,
            difficultyRank = difficultyRank, minDailyFrequency = frequency,
        ),
        price = price,
        previousPrice = previousPrice,
    )

    // -- Sorting --

    @Test
    fun sortByPriceDescending() {
        val habits = listOf(makeHabit("a", price = 100), makeHabit("b", price = 500), makeHabit("c", price = 300))
        val sorted = HabitsViewModel.sortHabits(habits, SortOption.PRICE_DESC)
        assertEquals(listOf(500, 300, 100), sorted.map { it.price })
    }

    @Test
    fun sortByPriceAscending() {
        val habits = listOf(makeHabit("a", price = 500), makeHabit("b", price = 100), makeHabit("c", price = 300))
        val sorted = HabitsViewModel.sortHabits(habits, SortOption.PRICE_ASC)
        assertEquals(listOf(100, 300, 500), sorted.map { it.price })
    }

    @Test
    fun sortByDifficultyDescending() {
        val habits = listOf(
            makeHabit("a", difficultyRank = "b"),
            makeHabit("b", difficultyRank = "m"),
            makeHabit("c", difficultyRank = "a"),
        )
        val sorted = HabitsViewModel.sortHabits(habits, SortOption.DIFFICULTY_DESC)
        assertEquals(listOf("m", "b", "a"), sorted.map { it.habit.difficultyRank })
    }

    @Test
    fun sortByNewest() {
        val habits = listOf(
            makeHabit("a", createdAt = "2024-01-01T00:00:00"),
            makeHabit("b", createdAt = "2024-06-01T00:00:00"),
            makeHabit("c", createdAt = "2024-03-01T00:00:00"),
        )
        val sorted = HabitsViewModel.sortHabits(habits, SortOption.NEWEST)
        assertEquals(listOf("b", "c", "a"), sorted.map { it.habit.id })
    }

    @Test
    fun sortByOldest() {
        val habits = listOf(
            makeHabit("b", createdAt = "2024-06-01T00:00:00"),
            makeHabit("a", createdAt = "2024-01-01T00:00:00"),
        )
        val sorted = HabitsViewModel.sortHabits(habits, SortOption.OLDEST)
        assertEquals(listOf("a", "b"), sorted.map { it.habit.id })
    }

    @Test
    fun sortByFrequencyDescending() {
        val habits = listOf(
            makeHabit("a", frequency = 1.0),
            makeHabit("b", frequency = 3.0),
            makeHabit("c", frequency = null),
        )
        val sorted = HabitsViewModel.sortHabits(habits, SortOption.FREQUENCY_DESC)
        assertEquals(listOf("b", "a", "c"), sorted.map { it.habit.id })
    }

    // -- Trend formatting --

    @Test
    fun trendZeroWhenEqual() {
        val (text, dir) = HabitsViewModel.formatTrend(500, 500)
        assertEquals("0%", text)
        assertEquals(TrendDirection.NEUTRAL, dir)
    }

    @Test
    fun trendUpSmallPercentage() {
        val (text, dir) = HabitsViewModel.formatTrend(105, 100)
        assertEquals("+5%", text) // trailing .0 is stripped
        assertEquals(TrendDirection.UP, dir)
    }

    @Test
    fun trendDownLargePercentage() {
        val (text, dir) = HabitsViewModel.formatTrend(80, 100)
        assertEquals("-20%", text)
        assertEquals(TrendDirection.DOWN, dir)
    }

    @Test
    fun trendZeroWhenPreviousIsZero() {
        val (text, dir) = HabitsViewModel.formatTrend(100, 0)
        assertEquals("0%", text)
        assertEquals(TrendDirection.NEUTRAL, dir)
    }

    // -- Frequency formatting --

    @Test
    fun formatFrequencyRemovesTrailingZeros() {
        assertEquals("1", HabitsViewModel.formatFrequency(1.0))
        assertEquals("2.5", HabitsViewModel.formatFrequency(2.5))
        assertEquals("0.5", HabitsViewModel.formatFrequency(0.5))
    }

    // -- Form state --

    @Test
    fun habitFormStateIsEditingWhenHabitPresent() {
        val habit = makeHabit().habit
        val state = HabitFormState(editingHabit = habit, name = habit.name)
        assertTrue(state.isEditing)
    }

    @Test
    fun habitFormStateIsNotEditingWhenEmpty() {
        val state = HabitFormState()
        assertEquals(false, state.isEditing)
    }
}
