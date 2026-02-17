package com.tofustash.app.data.local.dao

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.tofustash.app.data.local.db.TofustashDatabase
import com.tofustash.app.data.local.entity.TradeEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class TradeDaoTest {

    private lateinit var db: TofustashDatabase
    private lateinit var dao: TradeDao

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TofustashDatabase::class.java,
        ).allowMainThreadQueries().build()
        dao = db.tradeDao()
    }

    @After
    fun teardown() {
        db.close()
    }

    private fun makeTrade(
        id: String = UUID.randomUUID().toString(),
        habitId: String? = null,
        rewardId: String? = null,
        amount: Int = 100,
        deletedAt: String? = null,
        isDirty: Boolean = false,
    ) = TradeEntity(
        id = id,
        userId = "user-1",
        habitId = habitId,
        rewardId = rewardId,
        amount = amount,
        createdAt = "2024-01-01T00:00:00",
        updatedAt = "2024-01-01T00:00:00",
        deletedAt = deletedAt,
        isDirty = isDirty,
    )

    @Test
    fun insertAndGetById() = runTest {
        val trade = makeTrade(habitId = "habit-1", amount = 50)
        dao.upsert(trade)

        val result = dao.getById(trade.id)
        assertEquals(50, result!!.amount)
        assertEquals("habit-1", result.habitId)
    }

    @Test
    fun getAllActiveExcludesSoftDeleted() = runTest {
        dao.upsert(makeTrade(habitId = "h1", amount = 100))
        dao.upsert(makeTrade(rewardId = "r1", amount = -50, deletedAt = "2024-01-02T00:00:00"))

        val results = dao.getAllActive("user-1").first()
        assertEquals(1, results.size)
        assertEquals(100, results[0].amount)
    }

    @Test
    fun getActiveBalanceCalculatesCorrectly() = runTest {
        dao.upsert(makeTrade(habitId = "h1", amount = 100))
        dao.upsert(makeTrade(habitId = "h2", amount = 200))
        dao.upsert(makeTrade(rewardId = "r1", amount = -75))
        // Deleted trade should not count
        dao.upsert(makeTrade(habitId = "h3", amount = 999, deletedAt = "2024-01-02T00:00:00"))

        val balance = dao.getActiveBalance("user-1")
        assertEquals(225, balance) // 100 + 200 - 75
    }

    @Test
    fun getActiveBalanceReturnsZeroWhenEmpty() = runTest {
        val balance = dao.getActiveBalance("user-1")
        assertEquals(0, balance)
    }

    @Test
    fun getDirtyReturnsOnlyDirtyTrades() = runTest {
        dao.upsert(makeTrade(habitId = "h1", isDirty = false))
        dao.upsert(makeTrade(rewardId = "r1", isDirty = true))

        val dirty = dao.getDirty("user-1")
        assertEquals(1, dirty.size)
        assertTrue(dirty[0].isDirty)
    }

    @Test
    fun getTradesForHabit() = runTest {
        val habitId = "habit-1"
        dao.upsert(makeTrade(habitId = habitId, amount = 50))
        dao.upsert(makeTrade(habitId = habitId, amount = 75))
        dao.upsert(makeTrade(habitId = "other-habit", amount = 100))
        dao.upsert(makeTrade(rewardId = "reward-1", amount = -25))

        val trades = dao.getActiveForHabit("user-1", habitId).first()
        assertEquals(2, trades.size)
    }

    @Test
    fun getTradesForReward() = runTest {
        val rewardId = "reward-1"
        dao.upsert(makeTrade(rewardId = rewardId, amount = -50))
        dao.upsert(makeTrade(rewardId = rewardId, amount = -75))
        dao.upsert(makeTrade(habitId = "habit-1", amount = 100))

        val trades = dao.getActiveForReward("user-1", rewardId).first()
        assertEquals(2, trades.size)
    }

    @Test
    fun upsertAllInsertsMultiple() = runTest {
        val trades = listOf(
            makeTrade(habitId = "h1", amount = 10),
            makeTrade(habitId = "h2", amount = 20),
        )
        dao.upsertAll(trades)

        val results = dao.getAllActive("user-1").first()
        assertEquals(2, results.size)
    }

    @Test
    fun clearDirtyFlags() = runTest {
        val id1 = UUID.randomUUID().toString()
        val id2 = UUID.randomUUID().toString()
        dao.upsert(makeTrade(id = id1, habitId = "h1", isDirty = true))
        dao.upsert(makeTrade(id = id2, rewardId = "r1", isDirty = true))

        dao.clearDirtyFlags(listOf(id1, id2))

        val dirty = dao.getDirty("user-1")
        assertTrue(dirty.isEmpty())
    }
}
