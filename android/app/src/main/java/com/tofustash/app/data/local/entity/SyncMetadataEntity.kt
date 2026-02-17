package com.tofustash.app.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "sync_metadata")
data class SyncMetadataEntity(
    @PrimaryKey val id: String = "default",
    @ColumnInfo(name = "last_sync") val lastSync: String? = null,
    @ColumnInfo(name = "last_full_sync") val lastFullSync: Long = 0L,
)
