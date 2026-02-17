package com.tofustash.app.data.repository

import android.util.Base64
import com.tofustash.app.data.remote.TokenManager
import com.tofustash.app.data.remote.api.AuthApi
import com.tofustash.app.data.remote.dto.AuthResponse
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.Response

@OptIn(ExperimentalCoroutinesApi::class)
class AuthRepositoryTest {

    private lateinit var authApi: AuthApi
    private lateinit var tokenManager: TokenManager
    private lateinit var authRepository: AuthRepository

    // JWT with sub="user-123" (header.payload.signature)
    // Payload: {"sub":"user-123","exp":9999999999}
    private val fakeJwt: String by lazy {
        val header = java.util.Base64.getUrlEncoder().withoutPadding()
            .encodeToString("""{"alg":"HS256"}""".toByteArray())
        val payload = java.util.Base64.getUrlEncoder().withoutPadding()
            .encodeToString("""{"sub":"user-123","exp":9999999999}""".toByteArray())
        "$header.$payload.fake-signature"
    }

    @Before
    fun setup() {
        authApi = mockk()
        tokenManager = mockk(relaxUnitFun = true)

        // Mock android.util.Base64 to use java.util.Base64
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getUrlDecoder().decode(firstArg<String>())
        }

        authRepository = AuthRepository(authApi, tokenManager)
    }

    @After
    fun teardown() {
        unmockkStatic(Base64::class)
    }

    @Test
    fun loginSuccessSavesSessionAndSetsAuthenticated() = runTest {
        val authResponse = AuthResponse(accessToken = fakeJwt, refreshToken = "refresh-tok")
        coEvery { authApi.login(any()) } returns Response.success(authResponse)

        val result = authRepository.login("test@example.com", "password123")

        assertTrue(result.isSuccess)
        coVerify {
            tokenManager.saveSession(fakeJwt, "refresh-tok", "user-123", isAnonymous = false)
        }
        val state = authRepository.authState.value
        assertTrue(state is AuthState.Authenticated)
        assertEquals("user-123", (state as AuthState.Authenticated).userId)
        assertEquals(false, state.isAnonymous)
    }

    @Test
    fun loginFailureReturnsError() = runTest {
        val errorBody = okhttp3.ResponseBody.create(
            "application/json".toMediaType(),
            """{"errors":[{"code":"INVALID","message":"Invalid credentials"}]}""",
        )
        coEvery { authApi.login(any()) } returns Response.error(401, errorBody)

        val result = authRepository.login("test@example.com", "password123")

        assertTrue(result.isFailure)
        assertEquals("Invalid credentials", result.exceptionOrNull()?.message)
    }

    @Test
    fun registerSuccessSavesSession() = runTest {
        val authResponse = AuthResponse(accessToken = fakeJwt, refreshToken = "refresh-tok")
        coEvery { authApi.register(any()) } returns Response.success(authResponse)

        val result = authRepository.register("test@example.com", "password123")

        assertTrue(result.isSuccess)
        coVerify {
            tokenManager.saveSession(fakeJwt, "refresh-tok", "user-123", isAnonymous = false)
        }
    }

    @Test
    fun claimSuccessUpdatesAnonymousToFalse() = runTest {
        val authResponse = AuthResponse(accessToken = fakeJwt, refreshToken = "refresh-tok")
        coEvery { authApi.claim(any()) } returns Response.success(authResponse)

        val result = authRepository.claim("test@example.com", "password123")

        assertTrue(result.isSuccess)
        val state = authRepository.authState.value
        assertTrue(state is AuthState.Authenticated)
        assertEquals(false, (state as AuthState.Authenticated).isAnonymous)
    }

    @Test
    fun logoutClearsTokensAndReAuthsAnonymously() = runTest {
        coEvery { tokenManager.getRefreshToken() } returns "refresh-tok"
        coEvery { authApi.logout(any()) } returns Response.success(
            com.tofustash.app.data.remote.dto.SuccessResponse(true),
        )
        // Anonymous re-auth
        coEvery { tokenManager.getDeviceId() } returns "device-123"
        val authResponse = AuthResponse(accessToken = fakeJwt, refreshToken = "new-refresh")
        coEvery { authApi.anonymous(any()) } returns Response.success(authResponse)

        val result = authRepository.logout()

        assertTrue(result.isSuccess)
        coVerify { tokenManager.clearTokens() }
        coVerify { authApi.anonymous(any()) }
    }

    @Test
    fun parseUserIdFromJwtExtractsSubClaim() {
        val userId = AuthRepository.parseUserIdFromJwt(fakeJwt)
        assertEquals("user-123", userId)
    }

    @Test
    fun initializeWithExistingTokensRestoresSession() = runTest {
        coEvery { tokenManager.getAccessToken() } returns fakeJwt
        coEvery { tokenManager.getUserId() } returns "user-123"
        coEvery { tokenManager.getIsAnonymous() } returns false
        coEvery { tokenManager.getRefreshToken() } returns "refresh-tok"
        val authResponse = AuthResponse(accessToken = fakeJwt, refreshToken = "new-refresh")
        coEvery { authApi.refreshTokens(any()) } returns Response.success(authResponse)

        authRepository.initialize()

        val state = authRepository.authState.value
        assertTrue(state is AuthState.Authenticated)
        assertEquals("user-123", (state as AuthState.Authenticated).userId)
    }

    @Test
    fun initializeWithoutTokensCreatesAnonymousSession() = runTest {
        coEvery { tokenManager.getAccessToken() } returns null
        coEvery { tokenManager.getDeviceId() } returns null
        val authResponse = AuthResponse(accessToken = fakeJwt, refreshToken = "refresh-tok")
        coEvery { authApi.anonymous(any()) } returns Response.success(authResponse)

        authRepository.initialize()

        val state = authRepository.authState.value
        assertTrue(state is AuthState.Authenticated)
        assertTrue((state as AuthState.Authenticated).isAnonymous)
        coVerify { tokenManager.saveDeviceId(any()) }
    }
}
