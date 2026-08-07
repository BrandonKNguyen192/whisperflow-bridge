package com.whisperbridge

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.whisperbridge.databinding.ActivityMainBinding
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val scanReq = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.apply(this)
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        ProfileManager.migrateIfNeeded(this)
        refreshProfileChips()
        updateStatusView()
        applyAccentToView(binding.root)

        binding.btnSettings.setOnClickListener { showSettingsDialog() }
        binding.btnSend.setOnClickListener { sendText("type") }
        binding.btnEnter.setOnClickListener { sendEnter() }
        binding.btnClipboard.setOnClickListener { sendText("clipboard") }

        binding.etText.setOnEditorActionListener { _, _, _ ->
            sendText("type")
            true
        }

        handlePairIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        applyAccentToView(binding.root)
    }

    // ── Accent application ───────────────────────────────────────

    private fun applyAccentToView(root: View) {
        val accent = ThemeManager.getAccentColor(this)
        applyAccentRecursive(root, accent)
    }

    private fun applyAccentRecursive(view: View, accent: Int) {
        if (view is MaterialButton) {
            val isFilled = view.backgroundTintList?.defaultColor?.let { Color.alpha(it) > 200 } ?: false
            if (isFilled) {
                view.backgroundTintList = ColorStateList.valueOf(accent)
                view.iconTint = ColorStateList.valueOf(Color.WHITE)
                view.setTextColor(Color.WHITE)
            } else {
                val strokeColor = view.strokeColor?.defaultColor ?: 0
                if (strokeColor != 0 && strokeColor != ContextCompat.getColor(view.context, R.color.border)) {
                    // This is an outlined accent button (like Enter)
                    view.strokeColor = ColorStateList.valueOf(accent)
                    view.setTextColor(accent)
                    view.iconTint = ColorStateList.valueOf(accent)
                }
            }
        }

        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                applyAccentRecursive(view.getChildAt(i), accent)
            }
        }
    }

    // ── Profile chips ────────────────────────────────────────────

    private fun refreshProfileChips() {
        val row = binding.profileChipRow
        row.removeAllViews()
        val profiles = ProfileManager.getAll(this)
        val activeIdx = ProfileManager.getActiveIndex(this)
        val accent = ThemeManager.getAccentColor(this)
        val accentSoft = ThemeManager.getAccentSoft(this)

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
                    setBackgroundColor(accentSoft)
                    setTextColor(accent)
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
            setTextColor(accent)
            setOnClickListener { promptAddProfile() }
        }
        row.addView(addChip)
    }

    private fun selectProfile(index: Int) {
        ProfileManager.setActiveIndex(this, index)
        refreshProfileChips()
        updateStatusView()
        vibrate()
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
                ProfileManager.add(this, ProfileManager.Profile(name, "", 9877, ""))
                refreshProfileChips()
                updateStatusView()
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
                updateStatusView()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ── Settings dialog ──────────────────────────────────────────

    private fun showSettingsDialog() {
        val profile = ProfileManager.getActive(this)
        val accent = ThemeManager.getAccentColor(this)
        val currentMode = ThemeManager.getThemeMode(this)
        val currentAccentHex = ThemeManager.getAccentHex(this)

        val scrollView = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                600 * resources.displayMetrics.density.toInt()
            )
        }

        val dialogView = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 24, 48, 16)
        }

        // ── Connection section ───────────────────────────────────
        val connLabel = TextView(this).apply {
            text = "CONNECTION"
            textSize = 11f
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_tertiary))
            letterSpacing = 0.08f
            typeface = Typeface.DEFAULT_BOLD
        }
        dialogView.addView(connLabel)

        val etHost = EditText(this).apply {
            hint = "Mac IP address"
            setText(profile?.host ?: "")
            inputType = InputType.TYPE_TEXT_VARIATION_URI
            setPadding(32, 28, 32, 28)
            textSize = 15f
            setBackgroundResource(R.drawable.bg_field_round)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 12 }
        }
        dialogView.addView(etHost)

        val etPort = EditText(this).apply {
            hint = "Port (default 9877)"
            setText((profile?.port ?: 9877).toString())
            inputType = InputType.TYPE_CLASS_NUMBER
            setPadding(32, 28, 32, 28)
            textSize = 15f
            setBackgroundResource(R.drawable.bg_field_round)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 12 }
        }
        dialogView.addView(etPort)

        val etToken = EditText(this).apply {
            hint = "Token (leave empty on home Wi‑Fi)"
            setText(profile?.token ?: "")
            inputType = InputType.TYPE_TEXT_VARIATION_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            setPadding(32, 28, 32, 28)
            textSize = 15f
            setBackgroundResource(R.drawable.bg_field_round)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 12 }
        }
        dialogView.addView(etToken)

        // Connection action buttons
        val connButtonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 16 }
        }

        val btnScan = MaterialButton(this).apply {
            text = "Scan"
            textSize = 13f
            isAllCaps = false
            setPadding(24, 0, 24, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                72
            ).apply { marginEnd = 12 }
            cornerRadius = 9999
            strokeWidth = 1
            strokeColor = ContextCompat.getColorStateList(this@MainActivity, R.color.border)
            setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.card_bg))
            setTextColor(accent)
            icon = ContextCompat.getDrawable(this@MainActivity, R.drawable.ic_qr)
            iconGravity = MaterialButton.ICON_GRAVITY_TEXT_START
            iconTint = ColorStateList.valueOf(accent)
        }
        connButtonRow.addView(btnScan)

        val btnTest = MaterialButton(this).apply {
            text = "Test"
            textSize = 13f
            isAllCaps = false
            setPadding(24, 0, 24, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                72
            )
            cornerRadius = 9999
            strokeWidth = 1
            strokeColor = ContextCompat.getColorStateList(this@MainActivity, R.color.border)
            setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.card_bg))
            setTextColor(accent)
        }
        connButtonRow.addView(btnTest)

        dialogView.addView(connButtonRow)

        // Divider
        val divider = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 1
            ).apply {
                topMargin = 24
                bottomMargin = 8
            }
            setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.border))
        }
        dialogView.addView(divider)

        // ── Appearance section ───────────────────────────────────
        val appearLabel = TextView(this).apply {
            text = "APPEARANCE"
            textSize = 11f
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_tertiary))
            letterSpacing = 0.08f
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 16 }
        }
        dialogView.addView(appearLabel)

        // Theme mode selector
        val themeLabel = TextView(this).apply {
            text = "Theme"
            textSize = 14f
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_primary))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 14 }
        }
        dialogView.addView(themeLabel)

        val themeModes = listOf(
            Triple("Light", ThemeManager.ThemeMode.LIGHT, "☀️"),
            Triple("Dark OLED", ThemeManager.ThemeMode.DARK_OLED, "🌑"),
            Triple("System", ThemeManager.ThemeMode.SYSTEM, "⚙️")
        )

        val themeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 8 }
        }

        lateinit var selectedThemeMode: ThemeManager.ThemeMode
        selectedThemeMode = currentMode

        themeModes.forEach { (label, mode, _) ->
            val chip = MaterialButton(this).apply {
                text = label
                textSize = 12f
                isAllCaps = false
                typeface = Typeface.DEFAULT_BOLD
                setPadding(18, 0, 18, 0)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    64
                ).apply { marginEnd = 8 }
                cornerRadius = 9999
                strokeWidth = 1
                strokeColor = ContextCompat.getColorStateList(this@MainActivity, R.color.border)
                if (mode == currentMode) {
                    setBackgroundColor(ThemeManager.getAccentSoft(this@MainActivity))
                    setTextColor(accent)
                } else {
                    setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.chip_bg))
                    setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_secondary))
                }
                setOnClickListener {
                    selectedThemeMode = mode
                    // Update chip visuals
                    for (j in 0 until themeRow.childCount) {
                        val c = themeRow.getChildAt(j) as MaterialButton
                        val m = themeModes[j].second
                        if (m == mode) {
                            c.setBackgroundColor(ThemeManager.getAccentSoft(this@MainActivity))
                            c.setTextColor(accent)
                        } else {
                            c.setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.chip_bg))
                            c.setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_secondary))
                        }
                    }
                }
            }
            themeRow.addView(chip)
        }
        dialogView.addView(themeRow)

        // Accent color picker
        val accentLabel = TextView(this).apply {
            text = "Accent color"
            textSize = 14f
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_primary))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 18 }
        }
        dialogView.addView(accentLabel)

        val accentGrid = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 10 }
        }
        lateinit var selectedAccentHex: String
        selectedAccentHex = currentAccentHex

        // Two rows of 4
        val accentGrid2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 8 }
        }

        ThemeManager.accentOptions.forEachIndexed { i, opt ->
            val swatch = FrameLayout(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    44 * resources.displayMetrics.density.toInt(),
                    44 * resources.displayMetrics.density.toInt()
                ).apply { marginEnd = 12 }
                val color = try { Color.parseColor(opt.hex) } catch (_: Exception) { Color.GRAY }
                val bg = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(color)
                }
                background = bg
                setOnClickListener {
                    selectedAccentHex = opt.hex
                    // Mark all swatches
                    markSwatches(listOf(accentGrid, accentGrid2), selectedAccentHex)
                }
            }

            // Checkmark overlay for selected
            if (opt.hex == currentAccentHex) {
                val check = TextView(this).apply {
                    text = "✓"
                    textSize = 18f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                }
                swatch.addView(check)
            }

            (if (i < 4) accentGrid else accentGrid2).addView(swatch)
        }

        dialogView.addView(accentGrid)
        dialogView.addView(accentGrid2)

        scrollView.addView(dialogView)

        val dialog = AlertDialog.Builder(this)
            .setTitle("Settings")
            .setView(scrollView)
            .setPositiveButton("Save") { _, _ ->
                // Save connection
                val host = etHost.text.toString().trim()
                val port = etPort.text.toString().trim().toIntOrNull() ?: 9877
                val token = etToken.text.toString().trim()
                val activeIdx = ProfileManager.getActiveIndex(this)
                val profiles = ProfileManager.getAll(this)
                if (activeIdx in profiles.indices) {
                    val updated = profiles[activeIdx].copy(host = host, port = port, token = token)
                    ProfileManager.update(this, activeIdx, updated)
                }

                // Save appearance
                val needsRecreate = selectedThemeMode != currentMode || selectedAccentHex != currentAccentHex
                ThemeManager.setThemeMode(this, selectedThemeMode)
                ThemeManager.setAccentHex(this, selectedAccentHex)

                refreshProfileChips()
                updateStatusView()

                if (needsRecreate) {
                    ThemeManager.apply(this)
                    recreate()
                }
            }
            .setNegativeButton("Cancel", null)
            .create()

        btnScan.setOnClickListener {
            dialog.dismiss()
            launchScan()
        }

        btnTest.setOnClickListener {
            btnTest.isEnabled = false
            btnTest.text = "Testing…"
            val host = etHost.text.toString().trim()
            val port = etPort.text.toString().trim().toIntOrNull() ?: 9877
            val token = etToken.text.toString().trim()

            lifecycleScope.launch {
                val result = if (token.isNotEmpty()) {
                    BridgeClient.probe(host, port, token)
                } else {
                    BridgeClient.healthCheck(host, port)
                }
                btnTest.isEnabled = true
                btnTest.text = if (result.ok) "✓ Connected" else "✗ Failed"
                btnTest.postDelayed({ btnTest.text = "Test" }, 2000)
            }
        }

        dialog.show()
    }

    private fun markSwatches(grids: List<ViewGroup>, selectedHex: String) {
        val options = ThemeManager.accentOptions
        var idx = 0
        for (grid in grids) {
            for (i in 0 until grid.childCount) {
                val swatch = grid.getChildAt(i) as? FrameLayout ?: continue
                swatch.removeAllViews()
                val opt = options.getOrNull(idx++) ?: continue
                if (opt.hex == selectedHex) {
                    val check = TextView(swatch.context).apply {
                        text = "✓"
                        textSize = 18f
                        setTextColor(Color.WHITE)
                        gravity = Gravity.CENTER
                        layoutParams = FrameLayout.LayoutParams(
                            FrameLayout.LayoutParams.MATCH_PARENT,
                            FrameLayout.LayoutParams.MATCH_PARENT
                        )
                    }
                    swatch.addView(check)
                }
            }
        }
    }

    // ── Connection helpers ───────────────────────────────────────

    private fun activeHostPort(): Pair<String, Int>? {
        val profile = ProfileManager.getActive(this) ?: return null
        val host = profile.host
        if (host.isEmpty()) {
            Toast.makeText(this, "No host configured — tap the gear icon", Toast.LENGTH_LONG).show()
            return null
        }
        return host to profile.port
    }

    private fun activeToken(): String = ProfileManager.getActive(this)?.token ?: ""

    private fun updateStatusView() {
        val profile = ProfileManager.getActive(this)
        val configured = profile != null && profile.host.isNotEmpty()
        binding.statusText.text = if (configured)
            "${profile!!.name} · ${profile.host}"
        else
            "Not connected"
        val color = if (configured) R.color.status_ok else R.color.status_idle
        binding.statusDot.setColorFilter(ContextCompat.getColor(this, color))
    }

    // ── Send actions ─────────────────────────────────────────────

    private fun sendText(mode: String) {
        val (host, port) = activeHostPort() ?: return
        val text = binding.etText.text.toString()
        if (text.isBlank()) {
            Toast.makeText(this, "Nothing to send", Toast.LENGTH_SHORT).show()
            return
        }

        binding.btnSend.isEnabled = false
        binding.btnClipboard.isEnabled = false

        lifecycleScope.launch {
            val result = BridgeClient.sendText(
                host, port, text, mode, "android-main", activeToken(),
                enterAfter = binding.cbEnterAfter.isChecked
            )
            binding.btnSend.isEnabled = true
            binding.btnClipboard.isEnabled = true

            if (result.ok) {
                vibrate()
                binding.etText.text?.clear()
                val label = if (mode == "clipboard") "Copied to Mac clipboard" else "Typed on Mac"
                Toast.makeText(this@MainActivity, label, Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this@MainActivity, "Failed: ${result.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun sendEnter() {
        val (host, port) = activeHostPort() ?: return

        binding.btnEnter.isEnabled = false
        lifecycleScope.launch {
            val result = BridgeClient.sendText(
                host, port, "", "enter", "android-main", activeToken(),
                enterAfter = false
            )
            binding.btnEnter.isEnabled = true
            if (result.ok) {
                vibrate()
                Toast.makeText(this@MainActivity, "Return key sent", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this@MainActivity, "Failed: ${result.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // ── Scan / Pairing ───────────────────────────────────────────

    private fun launchScan() {
        startActivityForResult(Intent(this, ScanActivity::class.java), scanReq)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == scanReq && resultCode == RESULT_OK) {
            refreshProfileChips()
            updateStatusView()
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
        ProfileManager.add(this, ProfileManager.Profile(name, parsed.host, parsed.port, parsed.token))
        refreshProfileChips()
        updateStatusView()
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
