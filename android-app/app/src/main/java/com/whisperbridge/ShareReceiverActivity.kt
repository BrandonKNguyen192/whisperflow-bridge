package com.whisperbridge

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.whisperbridge.databinding.ActivityShareReceiverBinding
import kotlinx.coroutines.launch

/**
 * Receives text shared from Whisper Flow (or any app) via Android's
 * Share sheet, then forwards it to the Mac bridge server.
 */
class ShareReceiverActivity : AppCompatActivity() {

    private lateinit var binding: ActivityShareReceiverBinding
    private val prefs by lazy { getSharedPreferences("bridge", MODE_PRIVATE) }
    private var sharedText: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityShareReceiverBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Extract shared text
        sharedText = when (intent?.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
            else -> ""
        }

        if (sharedText.isBlank()) {
            binding.tvPreview.text = "No text received"
            binding.btnSend.isEnabled = false
            return
        }

        binding.tvPreview.text = sharedText
        binding.tvCharCount.text = "${sharedText.length} characters"

        binding.btnSend.setOnClickListener { forward("type") }
        binding.btnClipboard.setOnClickListener { forward("clipboard") }
        binding.btnDismiss.setOnClickListener { finish() }

        // Auto-send if a host is configured
        val host = prefs.getString("host", "") ?: ""
        if (host.isNotEmpty()) {
            forward("type")
        }
    }

    private fun forward(mode: String) {
        val host = prefs.getString("host", "") ?: ""
        val port = prefs.getString("port", "9877")?.toIntOrNull() ?: 9877
        val token = prefs.getString("token", "") ?: ""

        if (host.isEmpty()) {
            binding.tvStatus.text = "⚠ No Mac IP configured — open the app first"
            binding.tvStatus.setTextColor(
                ContextCompat.getColor(this, R.color.status_err)
            )
            return
        }

        binding.btnSend.isEnabled = false
        binding.btnClipboard.isEnabled = false
        binding.tvStatus.text = "Sending…"
        binding.tvStatus.setTextColor(
            ContextCompat.getColor(this, R.color.status_idle)
        )
        binding.progress.visibility = View.VISIBLE

        lifecycleScope.launch {
            val result = BridgeClient.sendText(host, port, sharedText, mode, "whisperflow-share", token)
            binding.progress.visibility = View.GONE

            if (result.ok) {
                vibrate()
                val label = if (mode == "clipboard") "📋 Copied to Mac clipboard" else "✓ Typed on Mac"
                binding.tvStatus.text = label
                binding.tvStatus.setTextColor(
                    ContextCompat.getColor(this@ShareReceiverActivity, R.color.status_ok)
                )
                // Auto-close after a short delay on success
                binding.root.postDelayed({ finish() }, 1200)
            } else {
                binding.tvStatus.text = "✗ ${result.message}"
                binding.tvStatus.setTextColor(
                    ContextCompat.getColor(this@ShareReceiverActivity, R.color.status_err)
                )
                binding.btnSend.isEnabled = true
                binding.btnClipboard.isEnabled = true
            }
        }
    }

    private fun vibrate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(
                    VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(VIBRATOR_SERVICE) as Vibrator
                v.vibrate(VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE))
            }
        } catch (_: Exception) {}
    }
}
