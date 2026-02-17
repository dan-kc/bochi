package com.tofustash.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.tofustash.app.data.local.entity.RewardTagEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface RewardTagDao {

    @Upsert
    suspend fun upsert(rewardTag: RewardTagEntity)

    @Upsert
    suspend fun upsertAll(rewardTags: List<RewardTagEntity>)

    @Query("SELECT * FROM reward_tags WHERE reward_id = :rewardId AND deleted_at IS NULL")
    fun getActiveForReward(rewardId: String): Flow<List<RewardTagEntity>>

    @Query("SELECT * FROM reward_tags WHERE is_dirty = 1")
    suspend fun getDirty(): List<RewardTagEntity>

    @Query(
        "UPDATE reward_tags SET is_dirty = 0 WHERE reward_id = :rewardId AND tag_id = :tagId",
    )
    suspend fun clearDirtyFlag(rewardId: String, tagId: String)

    @Query("SELECT * FROM reward_tags WHERE updated_at > :since")
    suspend fun getUpdatedSince(since: String): List<RewardTagEntity>
}
