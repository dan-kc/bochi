package com.tofustash.app.ui.auth

import com.tofustash.app.data.repository.AuthException
import com.tofustash.app.data.repository.AuthRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LoginViewModelTest {

    private lateinit var authRepository: AuthRepository
    private lateinit var viewModel: LoginViewModel
    private val testDispatcher = UnconfinedTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        authRepository = mockk()
        viewModel = LoginViewModel(authRepository)
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    @Test
    fun initialStateIsEmpty() {
        val state = viewModel.uiState
        assertEquals("", state.email)
        assertEquals("", state.password)
        assertNull(state.emailError)
        assertNull(state.passwordError)
        assertNull(state.generalError)
        assertFalse(state.isLoading)
        assertFalse(state.isSuccess)
    }

    @Test
    fun onEmailChangedUpdatesState() {
        viewModel.onEmailChanged("test@example.com")
        assertEquals("test@example.com", viewModel.uiState.email)
    }

    @Test
    fun onPasswordChangedUpdatesState() {
        viewModel.onPasswordChanged("password123")
        assertEquals("password123", viewModel.uiState.password)
    }

    @Test
    fun loginWithInvalidEmailShowsError() {
        viewModel.onEmailChanged("bad-email")
        viewModel.onPasswordChanged("password123")
        viewModel.login()
        assertNotNull(viewModel.uiState.emailError)
    }

    @Test
    fun loginWithEmptyPasswordShowsError() {
        viewModel.onEmailChanged("test@example.com")
        viewModel.login()
        assertNotNull(viewModel.uiState.passwordError)
    }

    @Test
    fun loginWithValidCredentialsCallsRepository() {
        coEvery { authRepository.login(any(), any()) } returns Result.success(Unit)

        viewModel.onEmailChanged("test@example.com")
        viewModel.onPasswordChanged("password123")
        viewModel.login()

        coVerify { authRepository.login("test@example.com", "password123") }
        assertTrue(viewModel.uiState.isSuccess)
    }

    @Test
    fun loginFailureShowsGeneralError() {
        coEvery { authRepository.login(any(), any()) } returns
            Result.failure(AuthException("Invalid credentials"))

        viewModel.onEmailChanged("test@example.com")
        viewModel.onPasswordChanged("password123")
        viewModel.login()

        assertEquals("Invalid credentials", viewModel.uiState.generalError)
        assertFalse(viewModel.uiState.isSuccess)
    }

    @Test
    fun onEmailChangedClearsErrors() {
        viewModel.onEmailChanged("bad")
        viewModel.login()
        assertNotNull(viewModel.uiState.emailError)

        viewModel.onEmailChanged("test@example.com")
        assertNull(viewModel.uiState.emailError)
    }
}
