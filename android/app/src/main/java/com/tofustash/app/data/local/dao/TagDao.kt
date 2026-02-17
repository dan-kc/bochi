package com.tofustash.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.tofustash.app.data.local.entity.TagEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TagDao {

    @Upsert
    suspend fun upsert(tag: TagEntity)

    @Upsert
    suspend fun upsertAll(tags: List<TagEntity>)

    @Query("SELECT * FROM tags WHERE id = :id")
    suspend fun getById(id: String): TagEntity?

    @Query("SELECT * FROM tags WHERE user_id = :userId AND deleted_at IS NULL")
    fun getAllActive(userId: String): Flow<List<TagEntity>>

    @Query("SELECT * FROM tags WHERE user_id = :userId AND is_dirty = 1")
    suspend fun getDirty(userId: String): List<TagEntity>

    @Query("UPDATE tags SET is_dirty = 0 WHERE id IN (:ids)")
    suspend fun clearDirtyFlags(ids: List<String>)

    @Query("SELECT * FROM tags WHERE user_id = :userId AND updated_at > :since")
    suspend fun getUpdatedSince(userId: String, since: String): List<TagEntity>

    @Query("DELETE FROM tags WHERE user_id = :userId")
    suspend fun deleteAllForUser(userId: String)
}
