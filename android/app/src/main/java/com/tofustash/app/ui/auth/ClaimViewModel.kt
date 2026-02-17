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

data class ClaimUiState(
    val email: String = "",
    val password: String = "",
    val confirmPassword: String = "",
    val emailError: String? = null,
    val passwordError: String? = null,
    val confirmPasswordError: String? = null,
    val generalError: String? = null,
    val isLoading: Boolean = false,
    val isSuccess: Boolean = false,
)

@HiltViewModel
class ClaimViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {

    var uiState by mutableStateOf(ClaimUiState())
        private set

    fun onEmailChanged(email: String) {
        uiState = uiState.copy(email = email, emailError = null, generalError = null)
    }

    fun onPasswordChanged(password: String) {
        uiState = uiState.copy(password = password, passwordError = null, generalError = null)
    }

    fun onConfirmPasswordChanged(confirmPassword: String) {
        uiState = uiState.copy(
            confirmPassword = confirmPassword,
            confirmPasswordError = null,
            generalError = null,
        )
    }

    fun claim() {
        val emailError = AuthValidation.validateEmail(uiState.email)
        val passwordError = AuthValidation.validatePassword(uiState.password)
        val confirmError = AuthValidation.validateConfirmPassword(uiState.password, uiState.confirmPassword)

        if (emailError != null || passwordError != null || confirmError != null) {
            uiState = uiState.copy(
                emailError = emailError,
                passwordError = passwordError,
                confirmPasswordError = confirmError,
            )
            return
        }

        uiState = uiState.copy(isLoading = true, generalError = null)

        viewModelScope.launch {
            authRepository.claim(uiState.email, uiState.password)
                .onSuccess {
                    uiState = uiState.copy(isLoading = false, isSuccess = true)
                }
                .onFailure { e ->
                    uiState = uiState.copy(
                        isLoading = false,
                        generalError = e.message ?: "Account claim failed",
                    )
                }
        }
    }
}
