package com.tofustash.app.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.tofustash.app.ui.auth.ClaimScreen
import com.tofustash.app.ui.auth.ClaimViewModel
import com.tofustash.app.ui.auth.LoginScreen
import com.tofustash.app.ui.auth.LoginViewModel
import com.tofustash.app.ui.auth.RegisterScreen
import com.tofustash.app.ui.auth.RegisterViewModel
import com.tofustash.app.ui.habits.HabitsScreen
import com.tofustash.app.ui.habits.HabitsViewModel
import com.tofustash.app.ui.rewards.RewardsScreen
import com.tofustash.app.ui.rewards.RewardsViewModel
import com.tofustash.app.ui.settings.SettingsScreen
import com.tofustash.app.ui.settings.SettingsViewModel

private data class TabItem(
    val screen: Screen,
    val label: String,
    val icon: ImageVector,
)

private val tabs = listOf(
    TabItem(Screen.Habits, "Habits", Icons.Default.CheckCircle),
    TabItem(Screen.Rewards, "Rewards", Icons.Default.CardGiftcard),
    TabItem(Screen.Settings, "Settings", Icons.Default.Settings),
)

@Composable
fun AppNavigation() {
    val backStack = remember { listOf<Any>(Screen.Habits).toMutableStateList() }

    val currentScreen = backStack.lastOrNull()
    val showBottomNav = currentScreen is Screen.Habits ||
        currentScreen is Screen.Rewards ||
        currentScreen is Screen.Settings

    Scaffold(
        bottomBar = {
            if (showBottomNav) {
                TofustashBottomBar(
                    selectedScreen = currentScreen,
                    onTabSelected = { tab ->
                        if (backStack.lastOrNull() != tab) {
                            backStack.clear()
                            backStack.add(tab)
                        }
                    },
                )
            }
        },
    ) { padding ->
        NavDisplay(
            backStack = backStack,
            onBack = { backStack.removeLastOrNull() },
            entryDecorators = listOf(
                rememberSaveableStateHolderNavEntryDecorator(),
                rememberViewModelStoreNavEntryDecorator(),
            ),
            entryProvider = entryProvider {
                entry<Screen.Habits> {
                    val viewModel: HabitsViewModel = hiltViewModel()
                    HabitsScreen(viewModel, Modifier.padding(padding))
                }
                entry<Screen.Rewards> {
                    val viewModel: RewardsViewModel = hiltViewModel()
                    RewardsScreen(viewModel, Modifier.padding(padding))
                }
                entry<Screen.Settings> {
                    val viewModel: SettingsViewModel = hiltViewModel()
                    SettingsScreen(
                        viewModel = viewModel,
                        onNavigateToLogin = {
                            backStack.clear()
                            backStack.add(Screen.Login)
                        },
                        onNavigateToRegister = {
                            backStack.clear()
                            backStack.add(Screen.Register)
                        },
                        onNavigateToClaim = {
                            backStack.clear()
                            backStack.add(Screen.Claim)
                        },
                        modifier = Modifier.padding(padding),
                    )
                }
                entry<Screen.Login> {
                    val viewModel: LoginViewModel = hiltViewModel()
                    LoginScreen(
                        viewModel = viewModel,
                        onSuccess = {
                            backStack.clear()
                            backStack.add(Screen.Settings)
                        },
                        onNavigateToRegister = {
                            backStack.clear()
                            backStack.add(Screen.Register)
                        },
                        onBack = {
                            backStack.clear()
                            backStack.add(Screen.Settings)
                        },
                    )
                }
                entry<Screen.Register> {
                    val viewModel: RegisterViewModel = hiltViewModel()
                    RegisterScreen(
                        viewModel = viewModel,
                        onSuccess = {
                            backStack.clear()
                            backStack.add(Screen.Settings)
                        },
                        onNavigateToLogin = {
                            backStack.clear()
                            backStack.add(Screen.Login)
                        },
                        onBack = {
                            backStack.clear()
                            backStack.add(Screen.Settings)
                        },
                    )
                }
                entry<Screen.Claim> {
                    val viewModel: ClaimViewModel = hiltViewModel()
                    ClaimScreen(
                        viewModel = viewModel,
                        onSuccess = {
                            backStack.clear()
                            backStack.add(Screen.Settings)
                        },
                        onNavigateToLogin = {
                            backStack.clear()
                            backStack.add(Screen.Login)
                        },
                        onBack = {
                            backStack.clear()
                            backStack.add(Screen.Settings)
                        },
                    )
                }
            },
        )
    }
}

@Composable
private fun TofustashBottomBar(
    selectedScreen: Any,
    onTabSelected: (Screen) -> Unit,
) {
    NavigationBar {
        tabs.forEach { tab ->
            NavigationBarItem(
                selected = selectedScreen == tab.screen,
                onClick = { onTabSelected(tab.screen) },
                icon = { Icon(tab.icon, contentDescription = tab.label) },
                label = { Text(tab.label) },
            )
        }
    }
}
