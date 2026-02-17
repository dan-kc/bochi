package com.tofustash.app.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity

@Entity(tableName = "habit_tags", primaryKeys = ["habit_id", "tag_id"])
data class HabitTagEntity(
    @ColumnInfo(name = "habit_id") val habitId: String,
    @ColumnInfo(name = "tag_id") val tagId: String,
    @ColumnInfo(name = "created_at") val createdAt: String,
    @ColumnInfo(name = "updated_at") val updatedAt: String,
    @ColumnInfo(name = "deleted_at") val deletedAt: String? = null,
    @ColumnInfo(name = "is_dirty") val isDirty: Boolean = false,
)
