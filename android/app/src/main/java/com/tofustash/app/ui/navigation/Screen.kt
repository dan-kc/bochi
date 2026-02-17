package com.tofustash.app.ui.navigation

sealed interface Screen {
    // Main tabs
    data object Habits : Screen
    data object Rewards : Screen
    data object Settings : Screen

    // Auth flow
    data object Login : Screen
    data object Register : Screen
    data object Claim : Screen
}
