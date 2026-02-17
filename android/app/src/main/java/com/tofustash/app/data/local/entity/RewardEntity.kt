package com.tofustash.app.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "rewards")
data class RewardEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "user_id") val userId: String,
    val name: String,
    val description: String,
    @ColumnInfo(name = "created_at") val createdAt: String,
    @ColumnInfo(name = "updated_at") val updatedAt: String,
    @ColumnInfo(name = "deleted_at") val deletedAt: String? = null,
    @ColumnInfo(name = "hidden_until") val hiddenUntil: String? = null,
    @ColumnInfo(name = "max_daily_frequency") val maxDailyFrequency: Double? = null,
    @ColumnInfo(name = "damage_rank") val damageRank: String? = null,
    @ColumnInfo(name = "is_dirty") val isDirty: Boolean = false,
)
