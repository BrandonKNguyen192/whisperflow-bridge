package com.whisperbridge

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.whisperbridge.databinding.ActivityMainBinding
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences("bridge", MODE_PRIVATE) }
    private val scanReq = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Restore saved settings
        binding.etHost.setText(prefs.getString("host", ""))
        binding.etPort.setText(prefs.getString("port", "9877"))
        binding.etToken.setText(prefs.getString("token", ""))

        binding.btnConnect.setOnClickListener { testConnection() }
        binding.btnScan.setOnClickListener { launchScan() }
        binding.btnSend.setOnClickListener { sendText("type") }
        binding.btnClipboard.setOnClickListener { sendText("clipboard") }

        // Send on Enter (IME action)
        binding.etText.setOnEditorActionListener { _, _, _ ->
            sendText("type")
            true
        }

        updateStatus(null, false)
        handlePairIntent(intent)
    }

    override fun onPause() {
        super.onPause()
        prefs.edit()
            .putString("host", binding.etHost.text.toString().trim())
            .putString("port", binding.etPort.text.toString().trim())
            .putString("token", binding.etToken.text.toString().trim())
            .apply()
    }

    private fun hostPort(): Pair<String, Int>? {
        val host = binding.etHost.text.toString().trim()
        val port = binding.etPort.text.toString().trim().toIntOrNull() ?: 9877
        if (host.isEmpty()) {
            Toast.makeText(this, "Enter your Mac's IP address", Toast.LENGTH_SHORT).show()
            return null
        }
        return host to port
    }

    private fun token(): String = binding.etToken.text.toString().trim()

    private fun testConnection() {
        val (host, port) = hostPort() ?: return
        binding.btnConnect.isEnabled = false
        binding.statusDot.visibility = View.VISIBLE
        binding.statusText.text = "Connecting…"

        lifecycleScope.launch {
            val tok = token()
            val result = if (tok.isNotEmpty()) {
                BridgeClient.probe(host, port, tok)
            } else {
                BridgeClient.healthCheck(host, port)
            }
            binding.btnConnect.isEnabled = true
            updateStatus(result.message, result.ok)
        }
    }

    private fun sendText(mode: String) {
        val (host, port) = hostPort() ?: return
        val text = binding.etText.text.toString()
        if (text.isBlank()) {
            Toast.makeText(this, "Nothing to send", Toast.LENGTH_SHORT).show()
            return
        }

        binding.btnSend.isEnabled = false
        binding.btnClipboard.isEnabled = false

        lifecycleScope.launch {
            val result = BridgeClient.sendText(host, port, text, mode, "android-main", token())
            binding.btnSend.isEnabled = true
            binding.btnClipboard.isEnabled = true

            if (result.ok) {
                vibrate()
                binding.etText.text?.clear()
                val label = if (mode == "clipboard") "Copied to Mac clipboard" else "Typed on Mac"
                binding.statusText.text = label
                binding.statusDot.setColorFilter(
                    ContextCompat.getColor(this@MainActivity, R.color.status_ok)
                )
            } else {
                binding.statusText.text = "Failed: ${result.message}"
                binding.statusDot.setColorFilter(
                    ContextCompat.getColor(this@MainActivity, R.color.status_err)
                )
            }
        }
    }

    private fun updateStatus(message: String?, connected: Boolean) {
        binding.statusText.text = message ?: "Not connected"
        val color = if (connected) R.color.status_ok else R.color.status_idle
        binding.statusDot.setColorFilter(ContextCompat.getColor(this, color))
    }

    private fun launchScan() {
        startActivityForResult(Intent(this, ScanActivity::class.java), scanReq)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == scanReq && resultCode == RESULT_OK) {
            binding.etHost.setText(prefs.getString("host", ""))
            binding.etPort.setText(prefs.getString("port", "9877"))
            binding.etToken.setText(prefs.getString("token", ""))
            updateStatus("Paired via QR", true)
            vibrate()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handlePairIntent(intent)
    }

    private fun handlePairIntent(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme != "whisperbridge") return
        val parsed = Pairing.parse(data.toString()) ?: return
        binding.etHost.setText(parsed.host)
        binding.etPort.setText(parsed.port.toString())
        binding.etToken.setText(parsed.token)
        prefs.edit()
            .putString("host", parsed.host)
            .putString("port", parsed.port.toString())
            .putString("token", parsed.token)
            .apply()
        updateStatus("Paired via link", true)
        vibrate()
    }

    private fun vibrate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(
                    VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                v.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
            }
        } catch (_: Exception) {}
    }
}
