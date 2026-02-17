package com.tofustash.app.domain.validation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class AuthValidationTest {

    @Test
    fun validEmailReturnsNull() {
        assertNull(AuthValidation.validateEmail("test@example.com"))
    }

    @Test
    fun blankEmailReturnsError() {
        assertNotNull(AuthValidation.validateEmail(""))
        assertNotNull(AuthValidation.validateEmail("   "))
    }

    @Test
    fun invalidEmailFormatReturnsError() {
        assertNotNull(AuthValidation.validateEmail("not-an-email"))
        assertNotNull(AuthValidation.validateEmail("missing@domain"))
        assertNotNull(AuthValidation.validateEmail("@no-local.com"))
    }

    @Test
    fun emailTooLongReturnsError() {
        val longEmail = "a".repeat(250) + "@b.com"
        assertNotNull(AuthValidation.validateEmail(longEmail))
    }

    @Test
    fun validPasswordReturnsNull() {
        assertNull(AuthValidation.validatePassword("password123"))
        assertNull(AuthValidation.validatePassword("12345678"))
    }

    @Test
    fun emptyPasswordReturnsError() {
        assertEquals("Password is required", AuthValidation.validatePassword(""))
    }

    @Test
    fun shortPasswordReturnsError() {
        assertNotNull(AuthValidation.validatePassword("short"))
        assertNotNull(AuthValidation.validatePassword("1234567"))
    }

    @Test
    fun longPasswordReturnsError() {
        val longPassword = "a".repeat(65)
        assertNotNull(AuthValidation.validatePassword(longPassword))
    }

    @Test
    fun nonAsciiPasswordReturnsError() {
        assertNotNull(AuthValidation.validatePassword("password\u00E9\u00E9"))
    }

    @Test
    fun matchingConfirmPasswordReturnsNull() {
        assertNull(AuthValidation.validateConfirmPassword("password123", "password123"))
    }

    @Test
    fun emptyConfirmPasswordReturnsError() {
        assertNotNull(AuthValidation.validateConfirmPassword("password123", ""))
    }

    @Test
    fun mismatchedConfirmPasswordReturnsError() {
        val error = AuthValidation.validateConfirmPassword("password123", "different")
        assertEquals("Passwords do not match", error)
    }
}
