package com.whisperbridge

import android.net.Uri

/** Parses a pairing payload (from a scanned QR or a deep link) into host/port/token. */
object Pairing {
    /** True for the Tailscale CGNAT range 100.64.0.0/10. */
    fun isTailscale(host: String): Boolean {
        val parts = host.split(".")
        if (parts.size != 4) return false
        val a = parts[0].toIntOrNull() ?: return false
        val b = parts[1].toIntOrNull() ?: return false
        return a == 100 && b in 64..127
    }

    fun labelFor(host: String, suggestedName: String = ""): String {
        val cleaned = suggestedName
            .filter { it.isLetterOrDigit() || it == ' ' || it == '-' || it == '_' || it == '.' }
            .trim()
            .take(24)
        if (cleaned.isNotEmpty()) return cleaned
        return if (isTailscale(host)) "Tailscale" else "Mac"
    }

    data class Parsed(val host: String, val port: Int, val token: String, val name: String = "")

    fun parse(text: String): Parsed? {
        val t = text.trim()
        if (t.isEmpty()) return null
        return try {
            val u = Uri.parse(t)
            when (u.scheme) {
                // whisperbridge://pair?host=H&port=P&token=T
                "whisperbridge" -> {
                    val host = u.getQueryParameter("host")?.trim().orEmpty()
                    if (host.isEmpty()) null else Parsed(
                        host,
                        u.getQueryParameter("port")?.toIntOrNull() ?: 9877,
                        u.getQueryParameter("token").orEmpty(),
                        u.getQueryParameter("name").orEmpty(),
                    )
                }
                // tolerate http(s)://host:port?token=T
                "http", "https" -> {
                    val host = u.host?.trim().orEmpty()
                    if (host.isEmpty()) null else Parsed(
                        host,
                        if (u.port > 0) u.port else 9877,
                        u.getQueryParameter("token").orEmpty(),
                        u.getQueryParameter("name").orEmpty(),
                    )
                }
                // bare host:port
                else -> if (t.contains(":") && !t.contains(" ")) {
                    val h = t.substringBefore(":").trim()
                    val p = t.substringAfter(":").trim().toIntOrNull() ?: 9877
                    if (h.isEmpty()) null else Parsed(h, p, "")
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
