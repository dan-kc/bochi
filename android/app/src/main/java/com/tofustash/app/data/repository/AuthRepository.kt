package com.tofustash.app.data.repository

import android.util.Base64
import com.tofustash.app.data.remote.TokenManager
import com.tofustash.app.data.remote.api.AuthApi
import com.tofustash.app.data.remote.dto.AnonymousRequest
import com.tofustash.app.data.remote.dto.ClaimRequest
import com.tofustash.app.data.remote.dto.LoginRequest
import com.tofustash.app.data.remote.dto.LogoutRequest
import com.tofustash.app.data.remote.dto.RefreshRequest
import com.tofustash.app.data.remote.dto.RegisterRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

sealed interface AuthState {
    data object Loading : AuthState
    data object Unauthenticated : AuthState
    data class Authenticated(val userId: String, val isAnonymous: Boolean) : AuthState
}

@Singleton
class AuthRepository @Inject constructor(
    private val authApi: AuthApi,
    private val tokenManager: TokenManager,
) {
    private val _authState = MutableStateFlow<AuthState>(AuthState.Loading)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    suspend fun initialize() {
        val accessToken = tokenManager.getAccessToken()
        if (accessToken != null) {
            val userId = tokenManager.getUserId()
            val isAnonymous = tokenManager.getIsAnonymous()
            if (userId != null) {
                _authState.value = AuthState.Authenticated(userId, isAnonymous)
                tryRefreshTokens()
            } else {
                _authState.value = AuthState.Unauthenticated
            }
        } else {
            loginAnonymous()
        }
    }

    suspend fun login(email: String, password: String): Result<Unit> = runCatching {
        val response = authApi.login(LoginRequest(email, password))
        if (!response.isSuccessful) {
            throw AuthException(parseErrorMessage(response.errorBody()?.string()))
        }
        val body = response.body()!!
        val userId = parseUserIdFromJwt(body.accessToken)
        tokenManager.saveSession(body.accessToken, body.refreshToken, userId, isAnonymous = false)
        _authState.value = AuthState.Authenticated(userId, isAnonymous = false)
    }

    suspend fun register(email: String, password: String): Result<Unit> = runCatching {
        val response = authApi.register(RegisterRequest(email, password))
        if (!response.isSuccessful) {
            throw AuthException(parseErrorMessage(response.errorBody()?.string()))
        }
        val body = response.body()!!
        val userId = parseUserIdFromJwt(body.accessToken)
        tokenManager.saveSession(body.accessToken, body.refreshToken, userId, isAnonymous = false)
        _authState.value = AuthState.Authenticated(userId, isAnonymous = false)
    }

    suspend fun claim(email: String, password: String): Result<Unit> = runCatching {
        val response = authApi.claim(ClaimRequest(email, password))
        if (!response.isSuccessful) {
            throw AuthException(parseErrorMessage(response.errorBody()?.string()))
        }
        val body = response.body()!!
        val userId = parseUserIdFromJwt(body.accessToken)
        tokenManager.saveSession(body.accessToken, body.refreshToken, userId, isAnonymous = false)
        _authState.value = AuthState.Authenticated(userId, isAnonymous = false)
    }

    suspend fun logout(): Result<Unit> = runCatching {
        val refreshToken = tokenManager.getRefreshToken()
        if (refreshToken != null) {
            authApi.logout(LogoutRequest(refreshToken))
        }
        tokenManager.clearTokens()
        loginAnonymous()
    }

    private suspend fun loginAnonymous() {
        try {
            var deviceId = tokenManager.getDeviceId()
            if (deviceId == null) {
                deviceId = UUID.randomUUID().toString()
                tokenManager.saveDeviceId(deviceId)
            }
            val response = authApi.anonymous(AnonymousRequest(deviceId))
            if (response.isSuccessful) {
                val body = response.body()!!
                val userId = parseUserIdFromJwt(body.accessToken)
                tokenManager.saveSession(body.accessToken, body.refreshToken, userId, isAnonymous = true)
                _authState.value = AuthState.Authenticated(userId, isAnonymous = true)
            } else {
                _authState.value = AuthState.Unauthenticated
            }
        } catch (_: Exception) {
            _authState.value = AuthState.Unauthenticated
        }
    }

    private suspend fun tryRefreshTokens() {
        try {
            val refreshToken = tokenManager.getRefreshToken() ?: return
            val response = authApi.refreshTokens(RefreshRequest(refreshToken))
            if (response.isSuccessful) {
                val body = response.body()!!
                tokenManager.saveTokens(body.accessToken, body.refreshToken)
            }
        } catch (_: Exception) {
            // Keep existing session, will retry on next sync
        }
    }

    companion object {
        internal fun parseUserIdFromJwt(token: String): String {
            val parts = token.split(".")
            if (parts.size < 2) throw IllegalArgumentException("Invalid JWT")
            val payload = Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
            val json = Json.parseToJsonElement(String(payload)).jsonObject
            return json["sub"]?.jsonPrimitive?.content
                ?: throw IllegalArgumentException("No sub claim in JWT")
        }

        private fun parseErrorMessage(errorBody: String?): String {
            if (errorBody == null) return "Unknown error"
            return try {
                val json = Json.parseToJsonElement(errorBody).jsonObject
                val errors = json["errors"]
                if (errors != null) {
                    val arr = errors as? kotlinx.serialization.json.JsonArray
                    arr?.firstOrNull()?.jsonObject?.get("message")?.jsonPrimitive?.content
                        ?: "Unknown error"
                } else {
                    json["message"]?.jsonPrimitive?.content ?: "Unknown error"
                }
            } catch (_: Exception) {
                "Unknown error"
            }
        }
    }
}

class AuthException(message: String) : Exception(message)
