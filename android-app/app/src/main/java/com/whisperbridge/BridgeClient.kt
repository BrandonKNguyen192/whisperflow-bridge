package com.whisperbridge

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Lightweight HTTP client that talks to the Mac bridge server.
 * Uses only HttpURLConnection — no extra dependencies.
 */
object BridgeClient {

    data class Result(val ok: Boolean, val message: String)

    private const val TIMEOUT_MS = 5000

    /** Send text to the Mac server. */
    suspend fun sendText(
        host: String,
        port: Int,
        text: String,
        mode: String = "type",
        source: String = "android",
        token: String = ""
    ): Result = withContext(Dispatchers.IO) {
        try {
            val url = URL("http://$host:$port/send")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            if (token.isNotBlank()) conn.setRequestProperty("Authorization", "Bearer $token")
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            conn.doOutput = true

            val payload = JSONObject().apply {
                put("text", text)
                put("mode", mode)
                put("source", source)
            }

            conn.outputStream.use { os ->
                os.write(payload.toString().toByteArray())
            }

            val code = conn.responseCode
            val body = if (code in 200..299) {
                conn.inputStream.bufferedReader().readText()
            } else {
                conn.errorStream?.bufferedReader()?.readText() ?: ""
            }
            conn.disconnect()

            if (code in 200..299) {
                val json = JSONObject(body)
                if (json.optBoolean("ok", false)) {
                    Result(true, "Sent ${json.optInt("chars", text.length)} chars")
                } else {
                    Result(false, "Server error")
                }
            } else {
                Result(false, "HTTP $code")
            }
        } catch (e: Exception) {
            Result(false, e.message ?: "Connection failed")
        }
    }

    /** Quick health check to verify the server is reachable. */
    suspend fun healthCheck(host: String, port: Int): Result =
        withContext(Dispatchers.IO) {
            try {
                val url = URL("http://$host:$port/health")
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 3000
                conn.readTimeout = 3000
                val code = conn.responseCode
                conn.disconnect()
                if (code == 200) Result(true, "Connected")
                else Result(false, "HTTP $code")
            } catch (e: Exception) {
                Result(false, e.message ?: "Unreachable")
            }
        }

    /** Authenticated, side-effect-free reachability probe.
     *  POSTs empty text so nothing is typed: 401 = bad token, 400/2xx = token ok + reachable. */
    suspend fun probe(host: String, port: Int, token: String): Result =
        withContext(Dispatchers.IO) {
            try {
                val url = URL("http://$host:$port/send")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                if (token.isNotBlank()) conn.setRequestProperty("Authorization", "Bearer $token")
                conn.connectTimeout = 3000
                conn.readTimeout = 3000
                conn.doOutput = true
                conn.outputStream.use { os -> os.write("{\"text\":\"\"}".toByteArray()) }
                val code = conn.responseCode
                conn.disconnect()
                when {
                    code == 401 -> Result(false, "Bad token")
                    code in 200..499 -> Result(true, "Connected")
                    else -> Result(false, "HTTP $code")
                }
            } catch (e: Exception) {
                Result(false, e.message ?: "Unreachable")
            }
        }
}
