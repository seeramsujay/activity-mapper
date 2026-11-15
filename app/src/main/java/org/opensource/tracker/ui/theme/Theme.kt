package org.opensource.tracker.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// Brand & Accent Colors
val BrandGreen = Color(0xFF10B981)
val BrandCyan = Color(0xFF06B6D4)
val BrandAmber = Color(0xFFF59E0B)
val BrandRed = Color(0xFFEF4444)
val BrandPurple = Color(0xFF8B5CF6)

// Surface & Card Tints
val DarkBackground = Color(0xFF0F1216)
val DarkSurface = Color(0xFF181C22)
val DarkSurfaceVariant = Color(0xFF222832)
val OledBackground = Color(0xFF000000)
val OledSurface = Color(0xFF0A0C0E)

private val DarkColorScheme = darkColorScheme(
    primary = BrandGreen,
    onPrimary = Color.Black,
    primaryContainer = Color(0xFF064E3B),
    onPrimaryContainer = Color(0xFFA7F3D0),
    secondary = BrandCyan,
    onSecondary = Color.Black,
    tertiary = BrandAmber,
    background = DarkBackground,
    surface = DarkSurface,
    surfaceVariant = DarkSurfaceVariant,
    onBackground = Color(0xFFF3F4F6),
    onSurface = Color(0xFFF3F4F6),
    error = BrandRed
)

private val OledColorScheme = darkColorScheme(
    primary = BrandGreen,
    onPrimary = Color.Black,
    primaryContainer = Color(0xFF064E3B),
    onPrimaryContainer = Color(0xFFA7F3D0),
    secondary = BrandCyan,
    onSecondary = Color.Black,
    tertiary = BrandAmber,
    background = OledBackground,
    surface = OledSurface,
    surfaceVariant = Color(0xFF111418),
    onBackground = Color.White,
    onSurface = Color.White,
    error = BrandRed
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF059669),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD1FAE5),
    onPrimaryContainer = Color(0xFF064E3B),
    secondary = Color(0xFF0284C7),
    onSecondary = Color.White,
    tertiary = Color(0xFFD97706),
    background = Color(0xFFF8FAFC),
    surface = Color.White,
    surfaceVariant = Color(0xFFF1F5F9),
    onBackground = Color(0xFF0F172A),
    onSurface = Color(0xFF0F172A),
    error = Color(0xFFDC2626)
)

@Composable
fun TurnBackTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    isOled: Boolean = false,
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme: ColorScheme = when {
        isOled -> OledColorScheme
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
