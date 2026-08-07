package com.whisperbridge

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.whisperbridge.databinding.ActivityMainBinding
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val scanReq = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        ProfileManager.migrateIfNeeded(this)
        refreshProfileChips()
        loadActiveProfile()

        binding.btnSaveProfile.setOnClickListener { saveCurrentProfile() }
        binding.btnConnect.setOnClickListener { testConnection() }
        binding.btnScan.setOnClickListener { launchScan() }
        binding.btnSend.setOnClickListener { sendText("type") }
        binding.btnClipboard.setOnClickListener { sendText("clipboard") }

        binding.etText.setOnEditorActionListener { _, _, _ ->
            sendText("type")
            true
        }

        updateStatus(null, false)
        handlePairIntent(intent)
    }

    // ── Profile chips ────────────────────────────────────────────

    private fun refreshProfileChips() {
        val row = binding.profileChipRow
        row.removeAllViews()
        val profiles = ProfileManager.getAll(this)
        val activeIdx = ProfileManager.getActiveIndex(this)

        profiles.forEachIndexed { i, p ->
            val chip = MaterialButton(this).apply {
                text = p.name
                textSize = 13f
                isAllCaps = false
                typeface = Typeface.DEFAULT_BOLD
                setPadding(28, 0, 28, 0)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    72
                ).apply {
                    marginEnd = 12
                }
                cornerRadius = 9999
                strokeWidth = 1
                strokeColor = ContextCompat.getColorStateList(this@MainActivity, R.color.border)
                if (i == activeIdx) {
                    setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.green_soft))
                    setTextColor(ContextCompat.getColor(this@MainActivity, R.color.green_text))
                } else {
                    setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.chip_bg))
                    setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_secondary))
                }
                setOnClickListener { selectProfile(i) }
                setOnLongClickListener {
                    confirmDeleteProfile(i)
                    true
                }
            }
            row.addView(chip)
        }

        // "+" add chip
        val addChip = MaterialButton(this).apply {
            text = "+"
            textSize = 18f
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            setPadding(24, 0, 24, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                72
            )
            cornerRadius = 9999
            strokeWidth = 1
            strokeColor = ContextCompat.getColorStateList(this@MainActivity, R.color.border)
            setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.card_bg))
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.accent))
            setOnClickListener { promptAddProfile() }
        }
        row.addView(addChip)
    }

    private fun selectProfile(index: Int) {
        saveCurrentProfile()
        ProfileManager.setActiveIndex(this, index)
        loadActiveProfile()
        refreshProfileChips()
        updateStatus("Switched profile", false)
        vibrate()
    }

    private fun loadActiveProfile() {
        val p = ProfileManager.getActive(this)
        if (p != null) {
            binding.etHost.setText(p.host)
            binding.etPort.setText(p.port.toString())
            binding.etToken.setText(p.token)
        }
    }

    private fun saveCurrentProfile() {
        val profiles = ProfileManager.getAll(this)
        val idx = ProfileManager.getActiveIndex(this)
        if (idx in profiles.indices) {
            val updated = profiles[idx].copy(
                host = binding.etHost.text.toString().trim(),
                port = binding.etPort.text.toString().trim().toIntOrNull() ?: 9877,
                token = binding.etToken.text.toString().trim()
            )
            ProfileManager.update(this, idx, updated)
        }
    }

    private fun promptAddProfile() {
        val input = EditText(this).apply {
            hint = "Profile name (e.g. Mac Studio)"
            setPadding(32, 32, 32, 32)
            textSize = 16f
        }
        AlertDialog.Builder(this)
            .setTitle("New Profile")
            .setView(input)
            .setPositiveButton("Create") { _, _ ->
                val name = input.text.toString().trim().ifEmpty { "Mac" }
                ProfileManager.add(
                    this,
                    ProfileManager.Profile(name, "", 9877, "")
                )
                refreshProfileChips()
                loadActiveProfile()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun confirmDeleteProfile(index: Int) {
        val profiles = ProfileManager.getAll(this)
        if (index !in profiles.indices) return
        if (profiles.size <= 1) {
            Toast.makeText(this, "Can't delete the last profile", Toast.LENGTH_SHORT).show()
            return
        }
        val name = profiles[index].name
        AlertDialog.Builder(this)
            .setTitle("Delete \"$name\"?")
            .setMessage("This profile will be removed.")
            .setPositiveButton("Delete") { _, _ ->
                ProfileManager.remove(this, index)
                refreshProfileChips()
                loadActiveProfile()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ── Connection helpers ───────────────────────────────────────

    private fun hostPort(): Pair<String, Int>? {
        val host = binding.etHost.text.toString().trim()
        val port = binding.etPort.text.toString().trim().toIntOrNull() ?: 9877
        if (host.isEmpty()) {
            Toast.makeText(this, "Enter your Mac's IP address", Toast.LENGTH_LONG).show()
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
            val result = BridgeClient.sendText(host, port, text, mode, "android-main", token(), enterAfter = binding.cbEnterAfter.isChecked)
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
            loadActiveProfile()
            refreshProfileChips()
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

        val name = if (parsed.host.contains("100.")) "Tailscale" else "Mac"
        ProfileManager.add(
            this,
            ProfileManager.Profile(name, parsed.host, parsed.port, parsed.token)
        )
        refreshProfileChips()
        loadActiveProfile()
        updateStatus("Paired via link", true)
        vibrate()
    }

    // ── Haptics ──────────────────────────────────────────────────

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
