package com.tofustash.app.ui.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.tofustash.app.data.remote.api.AuthApi
import com.tofustash.app.data.remote.dto.ChangeEmailRequest
import com.tofustash.app.data.remote.dto.ChangePasswordRequest
import com.tofustash.app.data.repository.AuthRepository
import com.tofustash.app.data.repository.AuthState
import com.tofustash.app.domain.validation.AuthValidation
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PasswordDialogState(
    val currentPassword: String = "",
    val newPassword: String = "",
    val confirmPassword: String = "",
    val error: String? = null,
    val isLoading: Boolean = false,
    val isSuccess: Boolean = false,
)

data class EmailDialogState(
    val newEmail: String = "",
    val password: String = "",
    val error: String? = null,
    val isLoading: Boolean = false,
    val isSuccess: Boolean = false,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val authApi: AuthApi,
) : ViewModel() {

    val authState: StateFlow<AuthState> = authRepository.authState
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), AuthState.Loading)

    var passwordDialog by mutableStateOf<PasswordDialogState?>(null)
        private set

    var emailDialog by mutableStateOf<EmailDialogState?>(null)
        private set

    fun openPasswordDialog() {
        passwordDialog = PasswordDialogState()
    }

    fun closePasswordDialog() {
        passwordDialog = null
    }

    fun openEmailDialog() {
        emailDialog = EmailDialogState()
    }

    fun closeEmailDialog() {
        emailDialog = null
    }

    fun changePassword(currentPassword: String, newPassword: String, confirmPassword: String) {
        val passwordError = AuthValidation.validatePassword(newPassword)
        val confirmError = AuthValidation.validateConfirmPassword(newPassword, confirmPassword)
        if (currentPassword.isEmpty()) {
            passwordDialog = passwordDialog?.copy(error = "Current password is required")
            return
        }
        if (passwordError != null) {
            passwordDialog = passwordDialog?.copy(error = passwordError)
            return
        }
        if (confirmError != null) {
            passwordDialog = passwordDialog?.copy(error = confirmError)
            return
        }
        if (currentPassword == newPassword) {
            passwordDialog = passwordDialog?.copy(error = "New password must be different")
            return
        }

        passwordDialog = passwordDialog?.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val response = authApi.changePassword(
                    ChangePasswordRequest(currentPassword, newPassword),
                )
                if (response.isSuccessful) {
                    passwordDialog = passwordDialog?.copy(isLoading = false, isSuccess = true)
                } else {
                    passwordDialog = passwordDialog?.copy(
                        isLoading = false,
                        error = "Failed to change password",
                    )
                }
            } catch (_: Exception) {
                passwordDialog = passwordDialog?.copy(
                    isLoading = false,
                    error = "Network error",
                )
            }
        }
    }

    fun changeEmail(newEmail: String, password: String) {
        val emailError = AuthValidation.validateEmail(newEmail)
        if (emailError != null) {
            emailDialog = emailDialog?.copy(error = emailError)
            return
        }
        if (password.isEmpty()) {
            emailDialog = emailDialog?.copy(error = "Password is required")
            return
        }

        emailDialog = emailDialog?.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val response = authApi.changeEmail(
                    ChangeEmailRequest(newEmail, password),
                )
                if (response.isSuccessful) {
                    emailDialog = emailDialog?.copy(isLoading = false, isSuccess = true)
                } else {
                    emailDialog = emailDialog?.copy(
                        isLoading = false,
                        error = "Failed to change email",
                    )
                }
            } catch (_: Exception) {
                emailDialog = emailDialog?.copy(
                    isLoading = false,
                    error = "Network error",
                )
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
        }
    }
}
