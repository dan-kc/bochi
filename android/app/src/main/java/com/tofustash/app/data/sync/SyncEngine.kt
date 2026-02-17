package com.tofustash.app.data.sync

import com.tofustash.app.data.local.dao.HabitDao
import com.tofustash.app.data.local.dao.HabitTagDao
import com.tofustash.app.data.local.dao.RewardDao
import com.tofustash.app.data.local.dao.RewardTagDao
import com.tofustash.app.data.local.dao.SyncMetadataDao
import com.tofustash.app.data.local.dao.TagDao
import com.tofustash.app.data.local.dao.TradeDao
import com.tofustash.app.data.local.entity.SyncMetadataEntity
import com.tofustash.app.data.remote.api.SyncApi
import com.tofustash.app.data.remote.dto.SyncRequest
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SyncEngine @Inject constructor(
    private val syncApi: SyncApi,
    private val habitDao: HabitDao,
    private val rewardDao: RewardDao,
    private val tradeDao: TradeDao,
    private val tagDao: TagDao,
    private val habitTagDao: HabitTagDao,
    private val rewardTagDao: RewardTagDao,
    private val syncMetadataDao: SyncMetadataDao,
) {

    suspend fun sync(userId: String): Result<Unit> = runCatching {
        // Collect dirty entities
        val dirtyHabits = habitDao.getDirty(userId)
        val dirtyRewards = rewardDao.getDirty(userId)
        val dirtyTrades = tradeDao.getDirty(userId)
        val dirtyTags = tagDao.getDirty(userId)
        val dirtyHabitTags = habitTagDao.getDirty()
        val dirtyRewardTags = rewardTagDao.getDirty()

        // Build sync request with dirty entities mapped to DTOs
        val request = SyncRequest(
            habits = dirtyHabits.map { it.toDto() },
            rewards = dirtyRewards.map { it.toDto() },
            trades = dirtyTrades.map { it.toDto() },
            tags = dirtyTags.map { it.toDto() },
            habitTags = dirtyHabitTags.map { it.toDto() },
            rewardTags = dirtyRewardTags.map { it.toDto() },
        )

        // Push to server
        val response = syncApi.push(request)
        if (!response.isSuccessful) {
            throw RuntimeException("Sync failed: ${response.code()}")
        }

        val body = response.body() ?: throw RuntimeException("Empty sync response")

        // Apply server response to local DB
        if (body.habits.isNotEmpty()) {
            habitDao.upsertAll(body.habits.map { it.toEntity(userId) })
        }
        if (body.rewards.isNotEmpty()) {
            rewardDao.upsertAll(body.rewards.map { it.toEntity(userId) })
        }
        if (body.trades.isNotEmpty()) {
            tradeDao.upsertAll(body.trades.map { it.toEntity(userId) })
        }
        if (body.tags.isNotEmpty()) {
            tagDao.upsertAll(body.tags.map { it.toEntity(userId) })
        }
        if (body.habitTags.isNotEmpty()) {
            habitTagDao.upsertAll(body.habitTags.map { it.toEntity() })
        }
        if (body.rewardTags.isNotEmpty()) {
            rewardTagDao.upsertAll(body.rewardTags.map { it.toEntity() })
        }

        // Clear dirty flags on successfully pushed entities
        if (dirtyHabits.isNotEmpty()) {
            habitDao.clearDirtyFlags(dirtyHabits.map { it.id })
        }
        if (dirtyRewards.isNotEmpty()) {
            rewardDao.clearDirtyFlags(dirtyRewards.map { it.id })
        }
        if (dirtyTrades.isNotEmpty()) {
            tradeDao.clearDirtyFlags(dirtyTrades.map { it.id })
        }
        if (dirtyTags.isNotEmpty()) {
            tagDao.clearDirtyFlags(dirtyTags.map { it.id })
        }
        for (ht in dirtyHabitTags) {
            habitTagDao.clearDirtyFlag(ht.habitId, ht.tagId)
        }
        for (rt in dirtyRewardTags) {
            rewardTagDao.clearDirtyFlag(rt.rewardId, rt.tagId)
        }

        // Update sync metadata
        val metadata = syncMetadataDao.get()
        if (metadata == null) {
            syncMetadataDao.upsert(SyncMetadataEntity(lastSync = body.serverTime))
        } else {
            syncMetadataDao.updateLastSync(body.serverTime)
        }
    }
}
