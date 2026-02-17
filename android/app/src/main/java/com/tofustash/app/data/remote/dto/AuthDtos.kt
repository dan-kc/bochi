package com.tofustash.app.data.remote.dto

import kotlinx.serialization.Serializable

@Serializable
data class LoginRequest(
    val email: String,
    val password: String,
)

@Serializable
data class RegisterRequest(
    val email: String,
    val password: String,
)

@Serializable
data class AuthResponse(
    val accessToken: String,
    val refreshToken: String,
)

@Serializable
data class RefreshRequest(
    val refreshToken: String,
)

@Serializable
data class AnonymousRequest(
    val deviceId: String,
)

@Serializable
data class ClaimRequest(
    val email: String,
    val password: String,
)

@Serializable
data class ChangePasswordRequest(
    val currentPassword: String,
    val newPassword: String,
)

@Serializable
data class ChangeEmailRequest(
    val newEmail: String,
    val password: String,
)

@Serializable
data class SuccessResponse(
    val success: Boolean,
)

@Serializable
data class LogoutRequest(
    val refreshToken: String,
)
