package com.tofustash.app.data.sync

import com.tofustash.app.data.local.entity.HabitEntity
import com.tofustash.app.data.local.entity.HabitTagEntity
import com.tofustash.app.data.local.entity.RewardEntity
import com.tofustash.app.data.local.entity.RewardTagEntity
import com.tofustash.app.data.local.entity.TagEntity
import com.tofustash.app.data.local.entity.TradeEntity
import com.tofustash.app.data.remote.dto.HabitDto
import com.tofustash.app.data.remote.dto.HabitTagDto
import com.tofustash.app.data.remote.dto.RewardDto
import com.tofustash.app.data.remote.dto.RewardTagDto
import com.tofustash.app.data.remote.dto.TagDto
import com.tofustash.app.data.remote.dto.TradeDto

// -- Entity → DTO (for pushing to server) --

fun HabitEntity.toDto() = HabitDto(
    id = id, name = name, description = description,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
    hiddenUntil = hiddenUntil, minDailyFrequency = minDailyFrequency,
    difficultyRank = difficultyRank,
)

fun RewardEntity.toDto() = RewardDto(
    id = id, name = name, description = description,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
    hiddenUntil = hiddenUntil, maxDailyFrequency = maxDailyFrequency,
    damageRank = damageRank,
)

fun TradeEntity.toDto() = TradeDto(
    id = id, habitId = habitId, rewardId = rewardId, amount = amount,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

fun TagEntity.toDto() = TagDto(
    id = id, name = name, colorHex = colorHex,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

fun HabitTagEntity.toDto() = HabitTagDto(
    habitId = habitId, tagId = tagId,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

fun RewardTagEntity.toDto() = RewardTagDto(
    rewardId = rewardId, tagId = tagId,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
)

// -- DTO → Entity (for pulling from server) --

fun HabitDto.toEntity(userId: String) = HabitEntity(
    id = id, userId = userId, name = name, description = description,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
    hiddenUntil = hiddenUntil, minDailyFrequency = minDailyFrequency,
    difficultyRank = difficultyRank, isDirty = false,
)

fun RewardDto.toEntity(userId: String) = RewardEntity(
    id = id, userId = userId, name = name, description = description,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
    hiddenUntil = hiddenUntil, maxDailyFrequency = maxDailyFrequency,
    damageRank = damageRank, isDirty = false,
)

fun TradeDto.toEntity(userId: String) = TradeEntity(
    id = id, userId = userId, habitId = habitId, rewardId = rewardId,
    amount = amount, createdAt = createdAt,
    updatedAt = updatedAt ?: createdAt, deletedAt = deletedAt, isDirty = false,
)

fun TagDto.toEntity(userId: String) = TagEntity(
    id = id, userId = userId, name = name, colorHex = colorHex,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
    isDirty = false,
)

fun HabitTagDto.toEntity() = HabitTagEntity(
    habitId = habitId, tagId = tagId,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
    isDirty = false,
)

fun RewardTagDto.toEntity() = RewardTagEntity(
    rewardId = rewardId, tagId = tagId,
    createdAt = createdAt, updatedAt = updatedAt, deletedAt = deletedAt,
    isDirty = false,
)
