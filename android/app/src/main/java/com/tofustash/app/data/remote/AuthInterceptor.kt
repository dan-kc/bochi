package com.tofustash.app.data.remote

import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

class AuthInterceptor @Inject constructor(
    private val tokenManager: TokenManager,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()

        if (!request.url.encodedPath.startsWith("/api")) {
            return chain.proceed(request)
        }

        val token = runBlocking { tokenManager.getAccessToken() }
            ?: return chain.proceed(request)

        val authenticatedRequest = request.newBuilder()
            .header("Authorization", "Bearer $token")
            .build()
        return chain.proceed(authenticatedRequest)
    }
}
