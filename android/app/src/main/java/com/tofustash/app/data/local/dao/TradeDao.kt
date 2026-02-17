package com.tofustash.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.tofustash.app.data.local.entity.TradeEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TradeDao {

    @Upsert
    suspend fun upsert(trade: TradeEntity)

    @Upsert
    suspend fun upsertAll(trades: List<TradeEntity>)

    @Query("SELECT * FROM trades WHERE id = :id")
    suspend fun getById(id: String): TradeEntity?

    @Query("SELECT * FROM trades WHERE user_id = :userId AND deleted_at IS NULL")
    fun getAllActive(userId: String): Flow<List<TradeEntity>>

    @Query(
        "SELECT * FROM trades WHERE user_id = :userId AND habit_id = :habitId AND deleted_at IS NULL",
    )
    fun getActiveForHabit(userId: String, habitId: String): Flow<List<TradeEntity>>

    @Query(
        "SELECT * FROM trades WHERE user_id = :userId AND reward_id = :rewardId AND deleted_at IS NULL",
    )
    fun getActiveForReward(userId: String, rewardId: String): Flow<List<TradeEntity>>

    @Query(
        "SELECT COALESCE(SUM(amount), 0) FROM trades WHERE user_id = :userId AND deleted_at IS NULL",
    )
    suspend fun getActiveBalance(userId: String): Int

    @Query("SELECT * FROM trades WHERE user_id = :userId AND is_dirty = 1")
    suspend fun getDirty(userId: String): List<TradeEntity>

    @Query("UPDATE trades SET is_dirty = 0 WHERE id IN (:ids)")
    suspend fun clearDirtyFlags(ids: List<String>)

    @Query("SELECT * FROM trades WHERE user_id = :userId AND updated_at > :since")
    suspend fun getUpdatedSince(userId: String, since: String): List<TradeEntity>

    @Query("DELETE FROM trades WHERE user_id = :userId")
    suspend fun deleteAllForUser(userId: String)
}
