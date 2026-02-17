package com.tofustash.app.domain.validation

object AuthValidation {

    private val EMAIL_REGEX = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

    fun validateEmail(email: String): String? = when {
        email.isBlank() -> "Email is required"
        !EMAIL_REGEX.matches(email) -> "Invalid email address"
        email.length > 254 -> "Email is too long"
        else -> null
    }

    fun validatePassword(password: String): String? = when {
        password.isEmpty() -> "Password is required"
        password.length < 8 -> "Password must be at least 8 characters"
        password.length > 64 -> "Password must be at most 64 characters"
        !password.all { it.code in 0x20..0x7E } -> "Password must contain only ASCII characters"
        else -> null
    }

    fun validateConfirmPassword(password: String, confirmPassword: String): String? = when {
        confirmPassword.isEmpty() -> "Please confirm your password"
        confirmPassword != password -> "Passwords do not match"
        else -> null
    }
}
