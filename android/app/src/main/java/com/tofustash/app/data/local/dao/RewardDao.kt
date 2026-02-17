package com.tofustash.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.tofustash.app.data.local.entity.RewardEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface RewardDao {

    @Upsert
    suspend fun upsert(reward: RewardEntity)

    @Upsert
    suspend fun upsertAll(rewards: List<RewardEntity>)

    @Query("SELECT * FROM rewards WHERE id = :id")
    suspend fun getById(id: String): RewardEntity?

    @Query("SELECT * FROM rewards WHERE user_id = :userId AND deleted_at IS NULL")
    fun getAllActive(userId: String): Flow<List<RewardEntity>>

    @Query("SELECT * FROM rewards WHERE user_id = :userId AND is_dirty = 1")
    suspend fun getDirty(userId: String): List<RewardEntity>

    @Query("UPDATE rewards SET is_dirty = 0 WHERE id IN (:ids)")
    suspend fun clearDirtyFlags(ids: List<String>)

    @Query(
        "UPDATE rewards SET deleted_at = :deletedAt, updated_at = :updatedAt, is_dirty = 1 WHERE id = :id",
    )
    suspend fun softDelete(id: String, deletedAt: String, updatedAt: String)

    @Query("SELECT * FROM rewards WHERE user_id = :userId AND updated_at > :since")
    suspend fun getUpdatedSince(userId: String, since: String): List<RewardEntity>

    @Query("DELETE FROM rewards WHERE user_id = :userId")
    suspend fun deleteAllForUser(userId: String)
}
