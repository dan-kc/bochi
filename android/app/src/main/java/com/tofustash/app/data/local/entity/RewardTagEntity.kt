package com.tofustash.app.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity

@Entity(tableName = "reward_tags", primaryKeys = ["reward_id", "tag_id"])
data class RewardTagEntity(
    @ColumnInfo(name = "reward_id") val rewardId: String,
    @ColumnInfo(name = "tag_id") val tagId: String,
    @ColumnInfo(name = "created_at") val createdAt: String,
    @ColumnInfo(name = "updated_at") val updatedAt: String,
    @ColumnInfo(name = "deleted_at") val deletedAt: String? = null,
    @ColumnInfo(name = "is_dirty") val isDirty: Boolean = false,
)
