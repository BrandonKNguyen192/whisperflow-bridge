package com.whisperbridge

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import androidx.appcompat.app.AppCompatDelegate

import kotlin.math.roundToInt

/**
 * Manages theme mode (Light / Dark OLED / System) and accent color.
 * Persisted in SharedPreferences. Applies theme globally.
 */
object ThemeManager {

    enum class ThemeMode(val value: String) {
        LIGHT("light"),
        DARK_OLED("dark_oled"),
        SYSTEM("system")
    }

    data class AccentOption(
        val name: String,
        val hex: String
    )

    val accentOptions = listOf(
        AccentOption("Sage", "#2E7D46"),
        AccentOption("Sky", "#0EA5E9"),
        AccentOption("Rose", "#E11D48"),
        AccentOption("Amber", "#D97706"),
        AccentOption("Violet", "#7C3AED"),
        AccentOption("Teal", "#0D9488"),
        AccentOption("Ruby", "#DC2626"),
        AccentOption("Mint", "#059669")
    )

    private const val PREFS_NAME = "theme_prefs"
    private const val KEY_THEME_MODE = "theme_mode"
    private const val KEY_ACCENT_HEX = "accent_hex"
    private const val DEFAULT_ACCENT = "#2E7D46"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getThemeMode(ctx: Context): ThemeMode {
        val raw = prefs(ctx).getString(KEY_THEME_MODE, ThemeMode.SYSTEM.value) ?: ThemeMode.SYSTEM.value
        return ThemeMode.entries.find { it.value == raw } ?: ThemeMode.SYSTEM
    }

    fun setThemeMode(ctx: Context, mode: ThemeMode) {
        prefs(ctx).edit().putString(KEY_THEME_MODE, mode.value).apply()
    }

    fun getAccentHex(ctx: Context): String =
        prefs(ctx).getString(KEY_ACCENT_HEX, DEFAULT_ACCENT) ?: DEFAULT_ACCENT

    fun setAccentHex(ctx: Context, hex: String) {
        prefs(ctx).edit().putString(KEY_ACCENT_HEX, hex).apply()
    }

    /** Apply the stored theme mode to the current activity/process. */
    fun apply(ctx: Context) {
        val mode = when (getThemeMode(ctx)) {
            ThemeMode.LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            ThemeMode.DARK_OLED -> AppCompatDelegate.MODE_NIGHT_YES
            ThemeMode.SYSTEM -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
        }
        AppCompatDelegate.setDefaultNightMode(mode)
    }

    /** Get the accent color as an int. */
    fun getAccentColor(ctx: Context): Int {
        return try {
            Color.parseColor(getAccentHex(ctx))
        } catch (_: Exception) {
            Color.parseColor(DEFAULT_ACCENT)
        }
    }

    /** Derive a soft/tinted background version of the accent. */
    fun getAccentSoft(ctx: Context): Int {
        val accent = getAccentColor(ctx)
        val r = Color.red(accent)
        val g = Color.green(accent)
        val b = Color.blue(accent)
        // Lighten: blend 85% white in light mode, or darken for dark
        val isDark = when (getThemeMode(ctx)) {
            ThemeMode.DARK_OLED -> true
            ThemeMode.SYSTEM -> {
                val nightMode = ctx.resources.configuration.uiMode and
                        android.content.res.Configuration.UI_MODE_NIGHT_MASK
                nightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
            }
            ThemeMode.LIGHT -> false
        }
        return if (isDark) {
            // Dark mode soft: very dark with accent hue
            Color.rgb(
                (r * 0.18f).roundToInt(),
                (g * 0.18f).roundToInt(),
                (b * 0.18f).roundToInt()
            )
        } else {
            // Light mode soft: pastel tint
            Color.rgb(
                (r + (255 - r) * 0.82f).roundToInt(),
                (g + (255 - g) * 0.82f).roundToInt(),
                (b + (255 - b) * 0.82f).roundToInt()
            )
        }
    }
}
