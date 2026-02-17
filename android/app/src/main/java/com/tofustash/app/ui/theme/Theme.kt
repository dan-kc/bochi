package com.tofustash.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    // Primary
    primary = Emerald500,
    onPrimary = Zinc950,
    primaryContainer = Emerald600,
    onPrimaryContainer = Zinc50,

    // Secondary
    secondary = Zinc400,
    onSecondary = Zinc950,
    secondaryContainer = Zinc700,
    onSecondaryContainer = Zinc200,

    // Tertiary
    tertiary = Amber500,
    onTertiary = Zinc950,
    tertiaryContainer = Amber400,
    onTertiaryContainer = Zinc950,

    // Background & Surface (zinc-inspired)
    background = Zinc950,
    onBackground = Zinc50,
    surface = Zinc900,
    onSurface = Zinc50,
    surfaceVariant = Zinc800,
    onSurfaceVariant = Zinc400,
    surfaceContainerLowest = Zinc950,
    surfaceContainerLow = Zinc900,
    surfaceContainer = Zinc800,
    surfaceContainerHigh = Zinc700,
    surfaceContainerHighest = Zinc600,

    // Error
    error = Red500,
    onError = Zinc50,
    errorContainer = Red900,
    onErrorContainer = Red400,

    // Outline
    outline = Zinc600,
    outlineVariant = Zinc700,

    // Inverse
    inverseSurface = Zinc100,
    inverseOnSurface = Zinc900,
    inversePrimary = Emerald600,
)

@Composable
fun TofustashTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = Typography,
        content = content,
    )
}
