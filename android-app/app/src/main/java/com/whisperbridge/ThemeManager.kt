package com.whisperbridge

import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView

import kotlin.math.roundToInt

/**
 * Manages theme mode (Light / Earth / Dark OLED / System) and accent color.
 * Persisted in SharedPreferences. Applies theme globally.
 */
object ThemeManager {

    enum class ThemeMode(val value: String) {
        LIGHT("light"),
        EARTH("earth"),
        DARK_OLED("dark_oled"),
        SYSTEM("system")
    }

    data class Palette(
        val background: Int,
        val surface: Int,
        val card: Int,
        val input: Int,
        val textPrimary: Int,
        val textSecondary: Int,
        val textTertiary: Int,
        val border: Int,
        val chip: Int,
        val neutral: Int,
        val statusIdle: Int,
        val greenSoft: Int
    )

    private val earthPalette = Palette(
        background = Color.rgb(241, 238, 230),
        surface = Color.rgb(232, 227, 216),
        card = Color.rgb(251, 248, 241),
        input = Color.rgb(247, 243, 235),
        textPrimary = Color.rgb(43, 41, 35),
        textSecondary = Color.rgb(101, 95, 84),
        textTertiary = Color.rgb(138, 130, 116),
        border = Color.rgb(216, 209, 195),
        chip = Color.rgb(232, 225, 212),
        neutral = Color.rgb(132, 125, 113),
        statusIdle = Color.rgb(168, 157, 138),
        greenSoft = Color.rgb(232, 235, 219)
    )

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
            ThemeMode.EARTH -> AppCompatDelegate.MODE_NIGHT_NO
            ThemeMode.DARK_OLED -> AppCompatDelegate.MODE_NIGHT_YES
            ThemeMode.SYSTEM -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
        }
        AppCompatDelegate.setDefaultNightMode(mode)
    }

    fun isEarth(ctx: Context): Boolean = getThemeMode(ctx) == ThemeMode.EARTH

    /** Resolves a shared color against the Earth palette when that theme is active. */
    fun color(ctx: Context, resourceId: Int): Int {
        if (!isEarth(ctx)) return ContextCompat.getColor(ctx, resourceId)
        return when (resourceId) {
            R.color.bg -> earthPalette.background
            R.color.surface -> earthPalette.surface
            R.color.card_bg -> earthPalette.card
            R.color.input_bg -> earthPalette.input
            R.color.text_primary -> earthPalette.textPrimary
            R.color.text_secondary -> earthPalette.textSecondary
            R.color.text_tertiary -> earthPalette.textTertiary
            R.color.border, R.color.stroke -> earthPalette.border
            R.color.chip_bg -> earthPalette.chip
            R.color.neutral -> earthPalette.neutral
            R.color.status_idle -> earthPalette.statusIdle
            R.color.green_soft -> earthPalette.greenSoft
            else -> ContextCompat.getColor(ctx, resourceId)
        }
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
            ThemeMode.LIGHT, ThemeMode.EARTH -> false
        }
        return if (isDark) {
            // Dark mode soft: very dark with accent hue
            Color.rgb(
                (r * 0.18f).roundToInt(),
                (g * 0.18f).roundToInt(),
                (b * 0.18f).roundToInt()
            )
        } else {
            // Light themes: a quiet, pastel tint. Earth blends into its warm card surface.
            val base = if (isEarth(ctx)) earthPalette.card else Color.WHITE
            Color.rgb(
                (r + (Color.red(base) - r) * 0.82f).roundToInt(),
                (g + (Color.green(base) - g) * 0.82f).roundToInt(),
                (b + (Color.blue(base) - b) * 0.82f).roundToInt()
            )
        }
    }

    /** Applies the Earth surface palette to an already-inflated view hierarchy. */
    fun applyEarthPalette(root: View) {
        if (!isEarth(root.context)) return
        root.setBackgroundColor(earthPalette.background)
        applyEarthPaletteRecursive(root)
    }

    private fun applyEarthPaletteRecursive(view: View) {
        val context = view.context
        val accent = getAccentColor(context)
        when (view) {
            is MaterialCardView -> {
                // Frosted: translucent warm card over the ambient backdrop.
                view.setCardBackgroundColor(withAlpha(earthPalette.card, 200))
                view.strokeColor = withAlpha(earthPalette.border, 110)
            }
            is MaterialButton -> applyEarthButton(view, accent)
            is EditText -> {
                view.background = earthFieldDrawable(context, accent)
                view.setTextColor(earthPalette.textPrimary)
                view.setHintTextColor(earthPalette.textTertiary)
            }
            is CompoundButton -> {
                view.setTextColor(earthPalette.textSecondary)
                view.buttonTintList = ColorStateList.valueOf(accent)
            }
            is ImageButton -> view.imageTintList = ColorStateList.valueOf(earthPalette.textTertiary)
            is FrameLayout -> {
                // Only the trackpad pad takes the field treatment. Scroll containers
                // (HorizontalScrollView chip rows, NestedScrollView sheets) are also
                // FrameLayouts and must stay transparent — otherwise they paint a
                // stray outlined "track" behind the chips.
                if (view.id == R.id.trackpadSurface) {
                    view.background = earthPadDrawable(context)
                }
            }
            is TextView -> applyEarthTextColor(view)
        }

        if (view.id == R.id.accentLine) {
            view.background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(
                    Color.rgb(180, 112, 76),
                    Color.rgb(112, 133, 86),
                    Color.rgb(196, 154, 80)
                )
            )
        } else if (view.id == R.id.tipCallout) {
            view.background = roundedDrawable(
                context,
                withAlpha(earthPalette.greenSoft, 170),
                earthPalette.greenSoft,
                0
            )
        }

        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                applyEarthPaletteRecursive(view.getChildAt(index))
            }
        }
    }

    /** Alpha-preserving helper for translucent glass surfaces. */
    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

    private fun applyEarthButton(button: MaterialButton, accent: Int) {
        val isAccentAction = button.currentTextColor == accent ||
            button.contentDescription == "Add computer"
        val isPrimaryAction = button.id == R.id.btnSend ||
            button.id == R.id.btnSaveAll || button.id == R.id.btnSaveConnection
        val iconWasAccent = button.iconTint?.defaultColor == accent ||
            button.iconTint?.defaultColor == ContextCompat.getColor(button.context, R.color.accent)

        if (isPrimaryAction) {
            button.backgroundTintList = ColorStateList.valueOf(accent)
            button.setTextColor(Color.WHITE)
            button.iconTint = ColorStateList.valueOf(Color.WHITE)
        } else if (isAccentAction) {
            button.backgroundTintList = ColorStateList.valueOf(getAccentSoft(button.context))
            button.setTextColor(accent)
            button.iconTint = ColorStateList.valueOf(accent)
        } else {
            button.backgroundTintList = ColorStateList.valueOf(earthPalette.chip)
            button.setTextColor(earthPalette.textPrimary)
            button.iconTint = ColorStateList.valueOf(
                if (iconWasAccent) accent else earthPalette.textPrimary
            )
        }
    }

    private fun applyEarthTextColor(textView: TextView) {
        when (textView.currentTextColor) {
            ContextCompat.getColor(textView.context, R.color.text_primary) ->
                textView.setTextColor(earthPalette.textPrimary)
            ContextCompat.getColor(textView.context, R.color.text_secondary) ->
                textView.setTextColor(earthPalette.textSecondary)
            ContextCompat.getColor(textView.context, R.color.text_tertiary) ->
                textView.setTextColor(earthPalette.textTertiary)
        }
    }

    private fun earthFieldDrawable(context: Context, accent: Int): StateListDrawable {
        val background = StateListDrawable()
        background.addState(
            intArrayOf(android.R.attr.state_focused),
            roundedDrawable(context, earthPalette.input, accent, 2)
        )
        background.addState(
            intArrayOf(),
            roundedDrawable(context, earthPalette.input, earthPalette.border, 1)
        )
        return background
    }

    /** Trackpad pad in Earth colors — matches bg_pad_round (20dp radius). */
    private fun earthPadDrawable(context: Context): GradientDrawable =
        roundedDrawable(
            context,
            withAlpha(earthPalette.input, 200),
            withAlpha(earthPalette.border, 110),
            1,
            radiusDp = 20
        )

    private fun roundedDrawable(
        context: Context,
        fill: Int,
        stroke: Int,
        strokeWidthDp: Int,
        radiusDp: Int = 14
    ): GradientDrawable =
        GradientDrawable().apply {
            val density = context.resources.displayMetrics.density
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radiusDp * density
            setColor(fill)
            setStroke((strokeWidthDp * density).roundToInt(), stroke)
        }

    // ── Ambient glass backdrop ────────────────────────────────────

    /** Soft radial color blob used by the Liquid-Glass-style backdrop. */
    fun createAmbientBlob(context: Context, color: Int, alpha: Int, sizeDp: Int): View {
        val size = (sizeDp * context.resources.displayMetrics.density).roundToInt()
        return View(context).apply {
            val gd = GradientDrawable().apply {
                gradientType = GradientDrawable.RADIAL_GRADIENT
                colors = intArrayOf(
                    Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color)),
                    Color.TRANSPARENT
                )
                gradientRadius = size / 2f
            }
            background = gd
            layoutParams = FrameLayout.LayoutParams(size, size)
        }
    }

    /**
     * Fill a backdrop container with accent + brand blobs and start them
     * drifting. Call once per screen; safe to re-run on recreate.
     */
    fun setupAmbient(container: FrameLayout) {
        val context = container.context
        container.removeAllViews()
        val accent = getAccentColor(context)
        val blue = ContextCompat.getColor(context, R.color.grad_blue)
        val amber = ContextCompat.getColor(context, R.color.grad_amber)
        val isDark = when (getThemeMode(context)) {
            ThemeMode.DARK_OLED -> true
            ThemeMode.SYSTEM -> {
                val night = context.resources.configuration.uiMode and
                    android.content.res.Configuration.UI_MODE_NIGHT_MASK
                night == android.content.res.Configuration.UI_MODE_NIGHT_YES
            }
            ThemeMode.LIGHT, ThemeMode.EARTH -> false
        }

        val blobs = mutableListOf<View>()
        blobs += createAmbientBlob(context, accent, if (isDark) 120 else 85, 340).also { blob ->
            blob.translationX = -60 * context.resources.displayMetrics.density
            blob.translationY = -80 * context.resources.displayMetrics.density
            (blob.layoutParams as FrameLayout.LayoutParams).gravity = Gravity.TOP or Gravity.START
            container.addView(blob)
        }
        blobs += createAmbientBlob(context, blue, if (isDark) 95 else 65, 300).also { blob ->
            blob.translationX = 70 * context.resources.displayMetrics.density
            blob.translationY = -30 * context.resources.displayMetrics.density
            (blob.layoutParams as FrameLayout.LayoutParams).gravity = Gravity.TOP or Gravity.END
            container.addView(blob)
        }
        blobs += createAmbientBlob(context, amber, if (isDark) 85 else 55, 260).also { blob ->
            blob.translationX = -40 * context.resources.displayMetrics.density
            blob.translationY = 60 * context.resources.displayMetrics.density
            (blob.layoutParams as FrameLayout.LayoutParams).gravity = Gravity.BOTTOM or Gravity.START
            container.addView(blob)
        }
        MotionKit.startAmbientDrift(blobs)
    }
}
