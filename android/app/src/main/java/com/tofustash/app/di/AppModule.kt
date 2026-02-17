package com.tofustash.app.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.room.Room
import com.tofustash.app.data.local.dao.HabitDao
import com.tofustash.app.data.local.dao.HabitTagDao
import com.tofustash.app.data.local.dao.RewardDao
import com.tofustash.app.data.local.dao.RewardTagDao
import com.tofustash.app.data.local.dao.SyncMetadataDao
import com.tofustash.app.data.local.dao.TagDao
import com.tofustash.app.data.local.dao.TradeDao
import com.tofustash.app.data.local.db.TofustashDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): TofustashDatabase =
        Room.databaseBuilder(context, TofustashDatabase::class.java, "tofustash.db")
            .build()

    @Provides
    @Singleton
    fun provideDataStore(@ApplicationContext context: Context): DataStore<Preferences> =
        PreferenceDataStoreFactory.create {
            context.preferencesDataStoreFile("tofustash_prefs")
        }

    @Provides fun provideHabitDao(db: TofustashDatabase): HabitDao = db.habitDao()
    @Provides fun provideRewardDao(db: TofustashDatabase): RewardDao = db.rewardDao()
    @Provides fun provideTradeDao(db: TofustashDatabase): TradeDao = db.tradeDao()
    @Provides fun provideTagDao(db: TofustashDatabase): TagDao = db.tagDao()
    @Provides fun provideHabitTagDao(db: TofustashDatabase): HabitTagDao = db.habitTagDao()
    @Provides fun provideRewardTagDao(db: TofustashDatabase): RewardTagDao = db.rewardTagDao()
    @Provides fun provideSyncMetadataDao(db: TofustashDatabase): SyncMetadataDao = db.syncMetadataDao()
}
