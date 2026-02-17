package com.tofustash.app.data.repository

import com.tofustash.app.data.local.dao.HabitDao
import com.tofustash.app.data.local.entity.HabitEntity
import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HabitRepository @Inject constructor(
    private val habitDao: HabitDao,
) {
    suspend fun create(
        userId: String,
        name: String,
        description: String,
        difficultyRank: String? = null,
        minDailyFrequency: Double? = null,
        hiddenUntil: String? = null,
    ): HabitEntity {
        val now = Instant.now().toString()
        val habit = HabitEntity(
            id = UUID.randomUUID().toString(),
            userId = userId,
            name = name,
            description = description,
            createdAt = now,
            updatedAt = now,
            difficultyRank = difficultyRank,
            minDailyFrequency = minDailyFrequency,
            hiddenUntil = hiddenUntil,
            isDirty = true,
        )
        habitDao.upsert(habit)
        return habit
    }

    suspend fun update(habit: HabitEntity): HabitEntity {
        val updated = habit.copy(
            updatedAt = Instant.now().toString(),
            isDirty = true,
        )
        habitDao.upsert(updated)
        return updated
    }

    suspend fun softDelete(id: String) {
        val now = Instant.now().toString()
        habitDao.softDelete(id, deletedAt = now, updatedAt = now)
    }

    suspend fun getById(id: String): HabitEntity? = habitDao.getById(id)

    fun getAllActive(userId: String): Flow<List<HabitEntity>> = habitDao.getAllActive(userId)

    suspend fun getDirty(userId: String): List<HabitEntity> = habitDao.getDirty(userId)

    suspend fun clearDirtyFlags(ids: List<String>) = habitDao.clearDirtyFlags(ids)

    suspend fun upsertFromSync(habits: List<HabitEntity>) = habitDao.upsertAll(habits)
}
