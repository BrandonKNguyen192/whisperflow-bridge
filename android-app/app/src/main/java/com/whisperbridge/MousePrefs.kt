package com.whisperbridge

import android.content.Context
import android.content.SharedPreferences

/** Device-wide trackpad sensitivity (1-10), stored separately from profiles. */
object MousePrefs {

    private const val PREFS_NAME = "mouse_prefs"
    private const val KEY_SPEED = "speed"
    private const val KEY_TAP_TO_CLICK = "tap_to_click"
    private const val KEY_NATURAL_SCROLL = "natural_scroll"
    private const val KEY_AIR_SENS = "air_sens"
    private const val KEY_AIR_INVERT = "air_invert"
    private const val DEFAULT_SPEED = 4
    private const val DEFAULT_AIR_SENS = 5

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getSpeed(ctx: Context): Int =
        prefs(ctx).getInt(KEY_SPEED, DEFAULT_SPEED).coerceIn(1, 10)

    fun setSpeed(ctx: Context, speed: Int) {
        prefs(ctx).edit().putInt(KEY_SPEED, speed.coerceIn(1, 10)).apply()
    }

    fun getTapToClick(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_TAP_TO_CLICK, true)

    fun setTapToClick(ctx: Context, enabled: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_TAP_TO_CLICK, enabled).apply()
    }

    fun getNaturalScroll(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_NATURAL_SCROLL, true)

    fun setNaturalScroll(ctx: Context, enabled: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_NATURAL_SCROLL, enabled).apply()
    }

    fun getAirSens(ctx: Context): Int =
        prefs(ctx).getInt(KEY_AIR_SENS, DEFAULT_AIR_SENS).coerceIn(1, 10)

    fun setAirSens(ctx: Context, sens: Int) {
        prefs(ctx).edit().putInt(KEY_AIR_SENS, sens.coerceIn(1, 10)).apply()
    }

    fun getAirInvert(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_AIR_INVERT, false)

    fun setAirInvert(ctx: Context, enabled: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_AIR_INVERT, enabled).apply()
    }
}
