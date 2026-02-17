package com.tofustash.app.data.repository

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.tofustash.app.data.local.db.TofustashDatabase
import com.tofustash.app.data.local.entity.HabitEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class TradeRepositoryTest {

    private lateinit var db: TofustashDatabase
    private lateinit var repo: TradeRepository
    private val userId = "user-1"

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TofustashDatabase::class.java,
        ).allowMainThreadQueries().build()
        repo = TradeRepository(db.tradeDao())
    }

    @After
    fun teardown() {
        db.close()
    }

    private suspend fun seedHabit(id: String = "habit-1") {
        db.habitDao().upsert(
            HabitEntity(
                id = id, userId = userId, name = "Test", description = "",
                createdAt = "2024-01-01T00:00:00", updatedAt = "2024-01-01T00:00:00",
            ),
        )
    }

    @Test
    fun createHabitTradePositiveAmount() = runTest {
        val trade = repo.createHabitTrade(userId, "habit-1", 500)

        assertNotNull(trade.id)
        assertEquals("habit-1", trade.habitId)
        assertNull(trade.rewardId)
        assertEquals(500, trade.amount)
        assertTrue(trade.isDirty)
    }

    @Test
    fun createRewardTradeNegativeAmount() = runTest {
        val trade = repo.createRewardTrade(userId, "reward-1", 300)

        assertEquals("reward-1", trade.rewardId)
        assertNull(trade.habitId)
        assertEquals(-300, trade.amount)
        assertTrue(trade.isDirty)
    }

    @Test
    fun getBalanceSumsAllActiveTrades() = runTest {
        repo.createHabitTrade(userId, "h1", 500)
        repo.createHabitTrade(userId, "h2", 300)
        repo.createRewardTrade(userId, "r1", 200)

        val balance = repo.getBalance(userId)
        assertEquals(600, balance) // 500 + 300 - 200
    }

    @Test
    fun getTradesInPeriodCountsRecentTrades() = runTest {
        // Create trades with timestamps
        repo.createHabitTrade(userId, "h1", 100) // now
        repo.createHabitTrade(userId, "h1", 100) // now

        val count = repo.getTradesForHabitInPeriod(userId, "h1", 7)
        assertEquals(2, count)
    }

    @Test
    fun getTradesInPeriodDoesNotCountOtherHabits() = runTest {
        repo.createHabitTrade(userId, "h1", 100)
        repo.createHabitTrade(userId, "h2", 100)

        val count = repo.getTradesForHabitInPeriod(userId, "h1", 7)
        assertEquals(1, count)
    }

    @Test
    fun getAllActiveExcludesDeleted() = runTest {
        repo.createHabitTrade(userId, "h1", 100)
        val trade2 = repo.createRewardTrade(userId, "r1", 50)
        // Simulate soft delete
        db.tradeDao().upsert(trade2.copy(deletedAt = "2024-06-01T00:00:00"))

        val active = repo.getAllActive(userId).first()
        assertEquals(1, active.size)
    }
}
