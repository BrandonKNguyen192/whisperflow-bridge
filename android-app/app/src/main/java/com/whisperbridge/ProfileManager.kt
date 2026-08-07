package com.whisperbridge

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Manages multiple bridge profiles (one per Mac) stored in SharedPreferences.
 * Each profile has a name, host, port, and optional token.
 */
object ProfileManager {

    data class Profile(
        val name: String,
        val host: String,
        val port: Int,
        val token: String
    )

    private const val PREFS_NAME = "bridge_profiles"
    private const val KEY_PROFILES = "profiles_json"
    private const val KEY_ACTIVE = "active_index"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getAll(ctx: Context): List<Profile> {
        val json = prefs(ctx).getString(KEY_PROFILES, null) ?: return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                var name = obj.optString("name", "MacBook Pro ${i + 1}")
                if (name == "Mac") name = "MacBook Pro"
                Profile(
                    name = name,
                    host = obj.optString("host", ""),
                    port = obj.optInt("port", 9877),
                    token = obj.optString("token", "")
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun getActiveIndex(ctx: Context): Int = prefs(ctx).getInt(KEY_ACTIVE, 0)

    fun getActive(ctx: Context): Profile? {
        val all = getAll(ctx)
        val idx = getActiveIndex(ctx)
        return all.getOrNull(idx)
    }

    fun setActiveIndex(ctx: Context, index: Int) {
        prefs(ctx).edit().putInt(KEY_ACTIVE, index).apply()
    }

    fun save(ctx: Context, profiles: List<Profile>) {
        val arr = JSONArray()
        profiles.forEach { p ->
            arr.put(JSONObject().apply {
                put("name", p.name)
                put("host", p.host)
                put("port", p.port)
                put("token", p.token)
            })
        }
        prefs(ctx).edit().putString(KEY_PROFILES, arr.toString()).apply()
    }

    fun add(ctx: Context, profile: Profile) {
        val all = getAll(ctx).toMutableList()
        all.add(profile)
        save(ctx, all)
        setActiveIndex(ctx, all.size - 1)
    }

    fun update(ctx: Context, index: Int, profile: Profile) {
        val all = getAll(ctx).toMutableList()
        if (index in all.indices) {
            all[index] = profile
            save(ctx, all)
        }
    }

    fun remove(ctx: Context, index: Int) {
        val all = getAll(ctx).toMutableList()
        if (index in all.indices) {
            all.removeAt(index)
            save(ctx, all)
            // Adjust active index
            val active = getActiveIndex(ctx)
            if (active >= all.size) {
                setActiveIndex(ctx, maxOf(0, all.size - 1))
            } else if (active > index) {
                setActiveIndex(ctx, active - 1)
            }
        }
    }

    /** Migrate from old single-profile prefs (bridge) to new multi-profile system. */
    fun migrateIfNeeded(ctx: Context) {
        if (getAll(ctx).isNotEmpty()) return

        val oldPrefs = ctx.getSharedPreferences("bridge", Context.MODE_PRIVATE)
        val oldHost = oldPrefs.getString("host", null) ?: return
        val oldPort = oldPrefs.getString("port", "9877")?.toIntOrNull() ?: 9877
        val oldToken = oldPrefs.getString("token", "") ?: ""

        val profile = Profile("MacBook Pro", oldHost, oldPort, oldToken)
        save(ctx, listOf(profile))
        setActiveIndex(ctx, 0)
    }
}
