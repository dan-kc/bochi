package com.tofustash.app.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "habits")
data class HabitEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "user_id") val userId: String,
    val name: String,
    val description: String,
    @ColumnInfo(name = "created_at") val createdAt: String,
    @ColumnInfo(name = "updated_at") val updatedAt: String,
    @ColumnInfo(name = "deleted_at") val deletedAt: String? = null,
    @ColumnInfo(name = "hidden_until") val hiddenUntil: String? = null,
    @ColumnInfo(name = "min_daily_frequency") val minDailyFrequency: Double? = null,
    @ColumnInfo(name = "difficulty_rank") val difficultyRank: String? = null,
    @ColumnInfo(name = "is_dirty") val isDirty: Boolean = false,
)
