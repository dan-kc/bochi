package com.tofustash.app.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.tofustash.app.data.repository.AuthState

@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel,
    onNavigateToLogin: () -> Unit,
    onNavigateToRegister: () -> Unit,
    onNavigateToClaim: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val authState by viewModel.authState.collectAsState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text(
            text = "Settings",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = "App settings and preferences.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))

        when (val state = authState) {
            is AuthState.Loading -> {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
            }
            is AuthState.Unauthenticated -> {
                NotLoggedInCard(
                    onLogin = onNavigateToLogin,
                    onRegister = onNavigateToRegister,
                )
            }
            is AuthState.Authenticated -> {
                if (state.isAnonymous) {
                    AnonymousCard(
                        userId = state.userId,
                        onClaim = onNavigateToClaim,
                        onLogin = onNavigateToLogin,
                    )
                } else {
                    RegisteredSection(
                        userId = state.userId,
                        viewModel = viewModel,
                    )
                }
            }
        }
    }

    // Change password dialog
    val pwState = viewModel.passwordDialog
    if (pwState != null) {
        ChangePasswordDialog(
            state = pwState,
            onConfirm = viewModel::changePassword,
            onDismiss = viewModel::closePasswordDialog,
        )
    }

    // Change email dialog
    val emailState = viewModel.emailDialog
    if (emailState != null) {
        ChangeEmailDialog(
            state = emailState,
            onConfirm = viewModel::changeEmail,
            onDismiss = viewModel::closeEmailDialog,
        )
    }
}

@Composable
private fun AnonymousCard(
    userId: String,
    onClaim: () -> Unit,
    onLogin: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.tertiaryContainer,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(20.dp)) {
            Text(
                text = "Anonymous Account",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = userId.take(8) + "...",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = "Create an account to sync your data across devices and keep it safe.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
            )
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = onClaim,
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.onTertiaryContainer,
                        contentColor = MaterialTheme.colorScheme.tertiaryContainer,
                    ),
                ) {
                    Text("Create Account")
                }
                OutlinedButton(
                    onClick = onLogin,
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Text("Login")
                }
            }
        }
    }
}

@Composable
private fun NotLoggedInCard(
    onLogin: () -> Unit,
    onRegister: () -> Unit,
) {
    Surface(
        color = MaterialTheme.colorScheme.primaryContainer,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(20.dp)) {
            Text(
                text = "Get Started with Tofustash",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "Sync your habits across devices.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onRegister, shape = RoundedCornerShape(12.dp)) {
                    Text("Register")
                }
                OutlinedButton(onClick = onLogin, shape = RoundedCornerShape(12.dp)) {
                    Text("Login")
                }
            }
        }
    }
}

@Composable
private fun RegisteredSection(
    userId: String,
    viewModel: SettingsViewModel,
) {
    // Profile info
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = RoundedCornerShape(24.dp),
            ) {
                Icon(
                    Icons.Default.Person,
                    contentDescription = null,
                    modifier = Modifier.padding(12.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(
                    text = userId.take(8) + "...",
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    text = "Account synced",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
    Spacer(Modifier.height(16.dp))

    // Account settings
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            SettingsItem(
                label = "Change Email",
                onClick = viewModel::openEmailDialog,
            )
            SettingsItem(
                label = "Change Password",
                onClick = viewModel::openPasswordDialog,
            )
        }
    }
    Spacer(Modifier.height(16.dp))

    OutlinedButton(
        onClick = viewModel::logout,
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = MaterialTheme.colorScheme.error,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text("Log Out")
    }
}

@Composable
private fun SettingsItem(
    label: String,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        color = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
            )
            Icon(
                Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ChangePasswordDialog(
    state: PasswordDialogState,
    onConfirm: (currentPassword: String, newPassword: String, confirmPassword: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var current by remember { mutableStateOf(state.currentPassword) }
    var newPw by remember { mutableStateOf(state.newPassword) }
    var confirm by remember { mutableStateOf(state.confirmPassword) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Change Password") },
        text = {
            Column {
                if (state.error != null) {
                    Text(state.error, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                }
                if (state.isSuccess) {
                    Text("Password changed successfully!", color = MaterialTheme.colorScheme.primary)
                } else {
                    OutlinedTextField(
                        value = current,
                        onValueChange = { current = it },
                        label = { Text("Current Password") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = newPw,
                        onValueChange = { newPw = it },
                        label = { Text("New Password") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = confirm,
                        onValueChange = { confirm = it },
                        label = { Text("Confirm Password") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = {
            if (state.isSuccess) {
                TextButton(onClick = onDismiss) { Text("Done") }
            } else {
                TextButton(
                    onClick = { onConfirm(current, newPw, confirm) },
                    enabled = !state.isLoading,
                ) {
                    if (state.isLoading) CircularProgressIndicator(strokeWidth = 2.dp)
                    else Text("Change")
                }
            }
        },
        dismissButton = {
            if (!state.isSuccess) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
    )
}

@Composable
private fun ChangeEmailDialog(
    state: EmailDialogState,
    onConfirm: (newEmail: String, password: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var email by remember { mutableStateOf(state.newEmail) }
    var password by remember { mutableStateOf(state.password) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Change Email") },
        text = {
            Column {
                if (state.error != null) {
                    Text(state.error, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                }
                if (state.isSuccess) {
                    Text("Email changed successfully!", color = MaterialTheme.colorScheme.primary)
                } else {
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it },
                        label = { Text("New Email") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Password") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = {
            if (state.isSuccess) {
                TextButton(onClick = onDismiss) { Text("Done") }
            } else {
                TextButton(
                    onClick = { onConfirm(email, password) },
                    enabled = !state.isLoading,
                ) {
                    if (state.isLoading) CircularProgressIndicator(strokeWidth = 2.dp)
                    else Text("Change")
                }
            }
        },
        dismissButton = {
            if (!state.isSuccess) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
    )
}
