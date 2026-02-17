package com.tofustash.app.data.local.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.tofustash.app.data.local.entity.SyncMetadataEntity

@Dao
interface SyncMetadataDao {

    @Upsert
    suspend fun upsert(metadata: SyncMetadataEntity)

    @Query("SELECT * FROM sync_metadata WHERE id = 'default'")
    suspend fun get(): SyncMetadataEntity?

    @Query("UPDATE sync_metadata SET last_sync = :lastSync WHERE id = 'default'")
    suspend fun updateLastSync(lastSync: String)

    @Query("UPDATE sync_metadata SET last_full_sync = :timestamp WHERE id = 'default'")
    suspend fun updateLastFullSync(timestamp: Long)

    @Query("UPDATE sync_metadata SET last_sync = NULL WHERE id = 'default'")
    suspend fun clearLastSync()
}
