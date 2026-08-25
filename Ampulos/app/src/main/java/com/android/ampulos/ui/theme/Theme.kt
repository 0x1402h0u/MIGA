package com.android.ampulos.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import top.yukonga.miuix.kmp.theme.ColorSchemeMode
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.ThemeController

val LocalUseMiuix = compositionLocalOf { false }

private val DarkColorScheme = darkColorScheme(
    primary = Purple80,
    secondary = PurpleGrey80,
    tertiary = Pink80
)

private val LightColorScheme = lightColorScheme(
    primary = Purple40,
    secondary = PurpleGrey40,
    tertiary = Pink40
)

// 现代黑白配色方案
private val ModernLightColorScheme = lightColorScheme(
    primary = ModernBlack,
    onPrimary = ModernWhite,
    primaryContainer = ModernGray90,
    onPrimaryContainer = ModernBlack,
    secondary = ModernGray20,
    onSecondary = ModernWhite,
    secondaryContainer = ModernGray90,
    onSecondaryContainer = ModernBlack,
    tertiary = ModernGray80,
    onTertiary = ModernBlack,
    background = ModernWhite,
    onBackground = ModernBlack,
    surface = ModernWhite,
    onSurface = ModernBlack,
    surfaceVariant = ModernGray95,
    onSurfaceVariant = ModernGray20,
    outline = ModernGray80,
    outlineVariant = ModernGray90
)

private val ModernDarkColorScheme = darkColorScheme(
    primary = ModernWhite,
    onPrimary = ModernBlack,
    primaryContainer = ModernGray20,
    onPrimaryContainer = ModernWhite,
    secondary = ModernGray80,
    onSecondary = ModernBlack,
    secondaryContainer = ModernGray20,
    onSecondaryContainer = ModernWhite,
    tertiary = ModernGray20,
    onTertiary = ModernWhite,
    background = ModernBlack,
    onBackground = ModernWhite,
    surface = ModernBlack,
    onSurface = ModernWhite,
    surfaceVariant = ModernGray10,
    onSurfaceVariant = ModernGray80,
    outline = ModernGray20,
    outlineVariant = ModernGray10
)

@Composable
fun AmpulosTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    useModernStyle: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        useModernStyle && darkTheme -> ModernDarkColorScheme
        useModernStyle -> ModernLightColorScheme
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = Color.Transparent.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}

@Composable
fun MiuixAppTheme(
    content: @Composable () -> Unit
) {
    val darkTheme = isSystemInDarkTheme()
    val colorSchemeMode = if (darkTheme) ColorSchemeMode.Dark else ColorSchemeMode.Light
    val controller = remember(colorSchemeMode) { ThemeController(colorSchemeMode) }

    CompositionLocalProvider(LocalUseMiuix provides true) {
        MiuixTheme(controller = controller, content = content)
    }
}
