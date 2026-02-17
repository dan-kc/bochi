package com.tofustash.app.data.repository

import com.tofustash.app.data.local.dao.RewardDao
import com.tofustash.app.data.local.entity.RewardEntity
import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RewardRepository @Inject constructor(
    private val rewardDao: RewardDao,
) {
    suspend fun create(
        userId: String,
        name: String,
        description: String,
        damageRank: String? = null,
        maxDailyFrequency: Double? = null,
        hiddenUntil: String? = null,
    ): RewardEntity {
        val now = Instant.now().toString()
        val reward = RewardEntity(
            id = UUID.randomUUID().toString(),
            userId = userId,
            name = name,
            description = description,
            createdAt = now,
            updatedAt = now,
            damageRank = damageRank,
            maxDailyFrequency = maxDailyFrequency,
            hiddenUntil = hiddenUntil,
            isDirty = true,
        )
        rewardDao.upsert(reward)
        return reward
    }

    suspend fun update(reward: RewardEntity): RewardEntity {
        val updated = reward.copy(
            updatedAt = Instant.now().toString(),
            isDirty = true,
        )
        rewardDao.upsert(updated)
        return updated
    }

    suspend fun softDelete(id: String) {
        val now = Instant.now().toString()
        rewardDao.softDelete(id, deletedAt = now, updatedAt = now)
    }

    suspend fun getById(id: String): RewardEntity? = rewardDao.getById(id)

    fun getAllActive(userId: String): Flow<List<RewardEntity>> = rewardDao.getAllActive(userId)

    suspend fun getDirty(userId: String): List<RewardEntity> = rewardDao.getDirty(userId)

    suspend fun clearDirtyFlags(ids: List<String>) = rewardDao.clearDirtyFlags(ids)

    suspend fun upsertFromSync(rewards: List<RewardEntity>) = rewardDao.upsertAll(rewards)
}
