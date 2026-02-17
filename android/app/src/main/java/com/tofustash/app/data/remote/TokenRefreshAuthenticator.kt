package com.tofustash.app.data.remote

import com.tofustash.app.data.remote.dto.RefreshRequest
import kotlinx.coroutines.runBlocking
import okhttp3.Authenticator
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import javax.inject.Inject

class TokenRefreshAuthenticator @Inject constructor(
    private val tokenManager: TokenManager,
    private val authApiProvider: dagger.Lazy<com.tofustash.app.data.remote.api.AuthApi>,
) : Authenticator {

    override fun authenticate(route: Route?, response: Response): Request? {
        if (responseCount(response) >= 2) return null

        val refreshToken = runBlocking { tokenManager.getRefreshToken() } ?: return null

        val authResponse = runBlocking {
            try {
                val result = authApiProvider.get().refreshTokens(RefreshRequest(refreshToken))
                if (result.isSuccessful) result.body() else null
            } catch (_: Exception) {
                null
            }
        } ?: run {
            runBlocking { tokenManager.clearTokens() }
            return null
        }

        runBlocking { tokenManager.saveTokens(authResponse.accessToken, authResponse.refreshToken) }

        return response.request.newBuilder()
            .header("Authorization", "Bearer ${authResponse.accessToken}")
            .build()
    }

    private fun responseCount(response: Response): Int {
        var count = 1
        var prior = response.priorResponse
        while (prior != null) {
            count++
            prior = prior.priorResponse
        }
        return count
    }
}
