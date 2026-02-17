package com.tofustash.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.tofustash.app.data.local.entity.HabitTagEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HabitTagDao {

    @Upsert
    suspend fun upsert(habitTag: HabitTagEntity)

    @Upsert
    suspend fun upsertAll(habitTags: List<HabitTagEntity>)

    @Query("SELECT * FROM habit_tags WHERE habit_id = :habitId AND deleted_at IS NULL")
    fun getActiveForHabit(habitId: String): Flow<List<HabitTagEntity>>

    @Query("SELECT * FROM habit_tags WHERE is_dirty = 1")
    suspend fun getDirty(): List<HabitTagEntity>

    @Query(
        "UPDATE habit_tags SET is_dirty = 0 WHERE habit_id = :habitId AND tag_id = :tagId",
    )
    suspend fun clearDirtyFlag(habitId: String, tagId: String)

    @Query("SELECT * FROM habit_tags WHERE updated_at > :since")
    suspend fun getUpdatedSince(since: String): List<HabitTagEntity>
}
