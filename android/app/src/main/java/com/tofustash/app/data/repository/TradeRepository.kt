package com.tofustash.app.data.repository

import com.tofustash.app.data.local.dao.TradeDao
import com.tofustash.app.data.local.entity.TradeEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TradeRepository @Inject constructor(
    private val tradeDao: TradeDao,
) {
    suspend fun createHabitTrade(userId: String, habitId: String, amount: Int): TradeEntity {
        val now = Instant.now().toString()
        val trade = TradeEntity(
            id = UUID.randomUUID().toString(),
            userId = userId,
            habitId = habitId,
            rewardId = null,
            amount = amount,
            createdAt = now,
            updatedAt = now,
            isDirty = true,
        )
        tradeDao.upsert(trade)
        return trade
    }

    suspend fun createRewardTrade(userId: String, rewardId: String, price: Int): TradeEntity {
        val now = Instant.now().toString()
        val trade = TradeEntity(
            id = UUID.randomUUID().toString(),
            userId = userId,
            habitId = null,
            rewardId = rewardId,
            amount = -price,
            createdAt = now,
            updatedAt = now,
            isDirty = true,
        )
        tradeDao.upsert(trade)
        return trade
    }

    suspend fun getBalance(userId: String): Int = tradeDao.getActiveBalance(userId)

    fun getAllActive(userId: String): Flow<List<TradeEntity>> = tradeDao.getAllActive(userId)

    suspend fun getTradesForHabitInPeriod(userId: String, habitId: String, days: Int): Int {
        val since = Instant.now().minus(days.toLong(), ChronoUnit.DAYS).toString()
        val trades = tradeDao.getActiveForHabit(userId, habitId).first()
        return trades.count { it.createdAt >= since }
    }

    suspend fun getTradesForRewardInPeriod(userId: String, rewardId: String, days: Int): Int {
        val since = Instant.now().minus(days.toLong(), ChronoUnit.DAYS).toString()
        val trades = tradeDao.getActiveForReward(userId, rewardId).first()
        return trades.count { it.createdAt >= since }
    }

    suspend fun getDirty(userId: String): List<TradeEntity> = tradeDao.getDirty(userId)

    suspend fun clearDirtyFlags(ids: List<String>) = tradeDao.clearDirtyFlags(ids)

    suspend fun upsertFromSync(trades: List<TradeEntity>) = tradeDao.upsertAll(trades)
}
