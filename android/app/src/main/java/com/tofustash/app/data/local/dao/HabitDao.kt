package com.tofustash.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.tofustash.app.data.local.entity.HabitEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HabitDao {

    @Upsert
    suspend fun upsert(habit: HabitEntity)

    @Upsert
    suspend fun upsertAll(habits: List<HabitEntity>)

    @Query("SELECT * FROM habits WHERE id = :id")
    suspend fun getById(id: String): HabitEntity?

    @Query("SELECT * FROM habits WHERE user_id = :userId AND deleted_at IS NULL")
    fun getAllActive(userId: String): Flow<List<HabitEntity>>

    @Query("SELECT * FROM habits WHERE user_id = :userId AND is_dirty = 1")
    suspend fun getDirty(userId: String): List<HabitEntity>

    @Query("UPDATE habits SET is_dirty = 0 WHERE id IN (:ids)")
    suspend fun clearDirtyFlags(ids: List<String>)

    @Query(
        "UPDATE habits SET deleted_at = :deletedAt, updated_at = :updatedAt, is_dirty = 1 WHERE id = :id",
    )
    suspend fun softDelete(id: String, deletedAt: String, updatedAt: String)

    @Query("SELECT * FROM habits WHERE user_id = :userId AND updated_at > :since")
    suspend fun getUpdatedSince(userId: String, since: String): List<HabitEntity>

    @Query("DELETE FROM habits WHERE user_id = :userId")
    suspend fun deleteAllForUser(userId: String)
}
