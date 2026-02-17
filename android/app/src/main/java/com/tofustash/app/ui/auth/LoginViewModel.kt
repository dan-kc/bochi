package com.tofustash.app.ui.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.tofustash.app.data.repository.AuthRepository
import com.tofustash.app.domain.validation.AuthValidation
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LoginUiState(
    val email: String = "",
    val password: String = "",
    val emailError: String? = null,
    val passwordError: String? = null,
    val generalError: String? = null,
    val isLoading: Boolean = false,
    val isSuccess: Boolean = false,
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {

    var uiState by mutableStateOf(LoginUiState())
        private set

    fun onEmailChanged(email: String) {
        uiState = uiState.copy(email = email, emailError = null, generalError = null)
    }

    fun onPasswordChanged(password: String) {
        uiState = uiState.copy(password = password, passwordError = null, generalError = null)
    }

    fun login() {
        val emailError = AuthValidation.validateEmail(uiState.email)
        val passwordError = AuthValidation.validatePassword(uiState.password)

        if (emailError != null || passwordError != null) {
            uiState = uiState.copy(emailError = emailError, passwordError = passwordError)
            return
        }

        uiState = uiState.copy(isLoading = true, generalError = null)

        viewModelScope.launch {
            authRepository.login(uiState.email, uiState.password)
                .onSuccess {
                    uiState = uiState.copy(isLoading = false, isSuccess = true)
                }
                .onFailure { e ->
                    uiState = uiState.copy(
                        isLoading = false,
                        generalError = e.message ?: "Login failed",
                    )
                }
        }
    }
}
