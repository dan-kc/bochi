package com.tofustash.app.data.local.db

import androidx.room.Database
import androidx.room.RoomDatabase
import com.tofustash.app.data.local.dao.HabitDao
import com.tofustash.app.data.local.dao.HabitTagDao
import com.tofustash.app.data.local.dao.RewardDao
import com.tofustash.app.data.local.dao.RewardTagDao
import com.tofustash.app.data.local.dao.SyncMetadataDao
import com.tofustash.app.data.local.dao.TagDao
import com.tofustash.app.data.local.dao.TradeDao
import com.tofustash.app.data.local.entity.HabitEntity
import com.tofustash.app.data.local.entity.HabitTagEntity
import com.tofustash.app.data.local.entity.RewardEntity
import com.tofustash.app.data.local.entity.RewardTagEntity
import com.tofustash.app.data.local.entity.SyncMetadataEntity
import com.tofustash.app.data.local.entity.TagEntity
import com.tofustash.app.data.local.entity.TradeEntity

@Database(
    entities = [
        HabitEntity::class,
        RewardEntity::class,
        TradeEntity::class,
        TagEntity::class,
        HabitTagEntity::class,
        RewardTagEntity::class,
        SyncMetadataEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class TofustashDatabase : RoomDatabase() {
    abstract fun habitDao(): HabitDao
    abstract fun rewardDao(): RewardDao
    abstract fun tradeDao(): TradeDao
    abstract fun tagDao(): TagDao
    abstract fun habitTagDao(): HabitTagDao
    abstract fun rewardTagDao(): RewardTagDao
    abstract fun syncMetadataDao(): SyncMetadataDao
}
