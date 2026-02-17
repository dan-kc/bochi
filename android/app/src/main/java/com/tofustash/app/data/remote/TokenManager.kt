package com.tofustash.app.data.remote

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TokenManager @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    private val accessTokenKey = stringPreferencesKey("access_token")
    private val refreshTokenKey = stringPreferencesKey("refresh_token")
    private val userIdKey = stringPreferencesKey("user_id")
    private val isAnonymousKey = booleanPreferencesKey("is_anonymous")
    private val deviceIdKey = stringPreferencesKey("device_id")

    suspend fun getAccessToken(): String? =
        dataStore.data.map { it[accessTokenKey] }.first()

    suspend fun getRefreshToken(): String? =
        dataStore.data.map { it[refreshTokenKey] }.first()

    suspend fun getUserId(): String? =
        dataStore.data.map { it[userIdKey] }.first()

    suspend fun getIsAnonymous(): Boolean =
        dataStore.data.map { it[isAnonymousKey] ?: true }.first()

    suspend fun getDeviceId(): String? =
        dataStore.data.map { it[deviceIdKey] }.first()

    suspend fun saveTokens(accessToken: String, refreshToken: String) {
        dataStore.edit {
            it[accessTokenKey] = accessToken
            it[refreshTokenKey] = refreshToken
        }
    }

    suspend fun saveSession(accessToken: String, refreshToken: String, userId: String, isAnonymous: Boolean) {
        dataStore.edit {
            it[accessTokenKey] = accessToken
            it[refreshTokenKey] = refreshToken
            it[userIdKey] = userId
            it[isAnonymousKey] = isAnonymous
        }
    }

    suspend fun saveDeviceId(deviceId: String) {
        dataStore.edit {
            it[deviceIdKey] = deviceId
        }
    }

    suspend fun clearTokens() {
        dataStore.edit {
            it.remove(accessTokenKey)
            it.remove(refreshTokenKey)
            it.remove(userIdKey)
            it.remove(isAnonymousKey)
        }
    }
}
