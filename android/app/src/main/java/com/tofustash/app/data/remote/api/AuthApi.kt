package com.tofustash.app.data.remote.api

import com.tofustash.app.data.remote.dto.AnonymousRequest
import com.tofustash.app.data.remote.dto.AuthResponse
import com.tofustash.app.data.remote.dto.ChangeEmailRequest
import com.tofustash.app.data.remote.dto.ChangePasswordRequest
import com.tofustash.app.data.remote.dto.ClaimRequest
import com.tofustash.app.data.remote.dto.LoginRequest
import com.tofustash.app.data.remote.dto.LogoutRequest
import com.tofustash.app.data.remote.dto.RefreshRequest
import com.tofustash.app.data.remote.dto.RegisterRequest
import com.tofustash.app.data.remote.dto.SuccessResponse
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.POST

interface AuthApi {

    @POST("auth/login")
    suspend fun login(@Body request: LoginRequest): Response<AuthResponse>

    @POST("auth/register")
    suspend fun register(@Body request: RegisterRequest): Response<AuthResponse>

    @POST("auth/logout")
    suspend fun logout(@Body request: LogoutRequest): Response<SuccessResponse>

    @POST("auth/refresh-tokens")
    suspend fun refreshTokens(@Body request: RefreshRequest): Response<AuthResponse>

    @POST("auth/anonymous")
    suspend fun anonymous(@Body request: AnonymousRequest): Response<AuthResponse>

    @POST("auth/claim")
    suspend fun claim(@Body request: ClaimRequest): Response<AuthResponse>

    @POST("auth/change-password")
    suspend fun changePassword(@Body request: ChangePasswordRequest): Response<SuccessResponse>

    @POST("auth/change-email")
    suspend fun changeEmail(@Body request: ChangeEmailRequest): Response<SuccessResponse>
}
