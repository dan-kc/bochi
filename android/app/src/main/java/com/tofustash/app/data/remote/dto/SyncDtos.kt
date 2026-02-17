package com.tofustash.app.data.remote.dto

import kotlinx.serialization.Serializable

@Serializable
data class HabitDto(
    val id: String,
    val name: String,
    val description: String,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String? = null,
    val hiddenUntil: String? = null,
    val minDailyFrequency: Double? = null,
    val difficultyRank: String? = null,
)

@Serializable
data class RewardDto(
    val id: String,
    val name: String,
    val description: String,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String? = null,
    val hiddenUntil: String? = null,
    val maxDailyFrequency: Double? = null,
    val damageRank: String? = null,
)

@Serializable
data class TradeDto(
    val id: String,
    val habitId: String? = null,
    val rewardId: String? = null,
    val amount: Int,
    val createdAt: String,
    val updatedAt: String? = null,
    val deletedAt: String? = null,
)

@Serializable
data class TagDto(
    val id: String,
    val name: String,
    val colorHex: String,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String? = null,
)

@Serializable
data class HabitTagDto(
    val habitId: String,
    val tagId: String,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String? = null,
)

@Serializable
data class RewardTagDto(
    val rewardId: String,
    val tagId: String,
    val createdAt: String,
    val updatedAt: String,
    val deletedAt: String? = null,
)

@Serializable
data class BalanceDto(
    val tofuBalance: Double,
)

@Serializable
data class SyncResponse(
    val habits: List<HabitDto> = emptyList(),
    val rewards: List<RewardDto> = emptyList(),
    val trades: List<TradeDto> = emptyList(),
    val tags: List<TagDto> = emptyList(),
    val habitTags: List<HabitTagDto> = emptyList(),
    val rewardTags: List<RewardTagDto> = emptyList(),
    val balance: BalanceDto,
    val serverTime: String,
    val email: String? = null,
    val isPremium: Boolean = false,
)

@Serializable
data class SyncRequest(
    val habits: List<HabitDto> = emptyList(),
    val rewards: List<RewardDto> = emptyList(),
    val trades: List<TradeDto> = emptyList(),
    val tags: List<TagDto> = emptyList(),
    val habitTags: List<HabitTagDto> = emptyList(),
    val rewardTags: List<RewardTagDto> = emptyList(),
)

@Serializable
data class ErrorResponse(
    val errors: List<ApiError>,
)

@Serializable
data class ApiError(
    val code: String,
    val message: String,
)
