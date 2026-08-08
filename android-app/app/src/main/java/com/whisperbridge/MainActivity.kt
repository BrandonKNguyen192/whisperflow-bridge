package com.whisperbridge

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.google.android.material.slider.Slider
import com.whisperbridge.databinding.ActivityMainBinding
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val scanReq = 1001

    private var dragActive = false
    private var dragButtonDown = false
    private var scrollActive = false
    private var lastTouchX = 0f
    private var lastTouchY = 0f
    private var lastScrollX = 0f
    private var lastScrollY = 0f
    private var lastMoveTime = 0L
    private var smoothVx = 0f
    private var smoothVy = 0f
    private var prevSmDx = 0f
    private var prevSmDy = 0f
    private var scrollVelX = 0f
    private var scrollVelY = 0f
    private var tapDownTime = 0L
    private var tapDownX = 0f
    private var tapDownY = 0f
    private var pendingMoveDx = 0
    private var pendingMoveDy = 0
    private var pendingScrollX = 0
    private var pendingScrollY = 0
    private var trackpadPinned = false
    private var mouseJob: Job? = null
    private var momentumJob: Job? = null
    private var mouseStatusJob: Job? = null
    private var sensorManager: SensorManager? = null
    private var gyroSensor: Sensor? = null
    private var airMouseActive = false
    private var lastGyroT = 0L
    private var airVx = 0f
    private var airVy = 0f

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
        binding.btnMouseLeft.setOnClickListener { sendMouseButton("click", "left", "Left click") }
        binding.btnMouseRight.setOnClickListener { sendMouseButton("click", "right", "Right click") }
        binding.btnMouseDouble.setOnClickListener { sendMouseButton("double_click", "left", "Double click") }
        binding.btnScrollUp.setOnClickListener { sendMouseButton("scroll", "left", "Scroll up", dy = 90) }
        binding.btnScrollDown.setOnClickListener { sendMouseButton("scroll", "left", "Scroll down", dy = -90) }
        binding.btnMouseDrag.setOnClickListener { toggleDragMode() }
        binding.trackpadSurface.setOnTouchListener { _, event -> onTrackpadTouch(event) }
        binding.btnPinTrackpad.setOnClickListener { toggleTrackpadPin() }
        binding.btnAirMouse.setOnTouchListener { v, ev ->
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    v.parent?.requestDisallowInterceptTouchEvent(true)
                    startAirMouse()
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.parent?.requestDisallowInterceptTouchEvent(false)
                    stopAirMouse()
                    true
                }
                else -> true
            }
        }

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

    override fun onPause() {
        super.onPause()
        if (airMouseActive) stopAirMouse()
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
                textSize = 14f
                isAllCaps = false
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                insetTop = 0
                insetBottom = 0
                setPadding(32, 0, 32, 0)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    60
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
            textSize = 20f
            isAllCaps = false
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            insetTop = 0
            insetBottom = 0
            setPadding(26, 0, 26, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                60
            )
            // The "+" glyph sits a hair low inside its pill due to font metrics.
            translationY = -1.5f * resources.displayMetrics.density
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
                val name = input.text.toString().trim().ifEmpty { "MacBook Pro" }
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
            letterSpacing = 0f
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
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                56
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
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                56
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
            letterSpacing = 0f
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
            Pair("Light", ThemeManager.ThemeMode.LIGHT),
            Pair("Dark OLED", ThemeManager.ThemeMode.DARK_OLED),
            Pair("System", ThemeManager.ThemeMode.SYSTEM)
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

        themeModes.forEach { (label, mode) ->
            val chip = MaterialButton(this).apply {
                text = label
                textSize = 12f
                isAllCaps = false
                typeface = Typeface.DEFAULT_BOLD
                setPadding(18, 0, 18, 0)
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    52
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

        val customAccent = MaterialButton(this).apply {
            text = "Custom color"
            textSize = 13f
            isAllCaps = false
            minWidth = 0
            cornerRadius = 12
            strokeWidth = 1
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            typeface = Typeface.DEFAULT_BOLD
            strokeColor = ContextCompat.getColorStateList(this@MainActivity, R.color.border)
            setBackgroundColor(ContextCompat.getColor(this@MainActivity, R.color.card_bg))
            setTextColor(accent)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                56
            ).apply { topMargin = 12 }
            setOnClickListener {
                showCustomAccentDialog(selectedAccentHex) { chosenHex ->
                    selectedAccentHex = chosenHex
                    markSwatches(listOf(accentGrid, accentGrid2), selectedAccentHex)
                    setTextColor(Color.parseColor(chosenHex))
                    text = "Custom $chosenHex"
                }
            }
        }
        dialogView.addView(customAccent)

        // ── Mouse section ─────────────────────────────────────────
        val mouseLabel = TextView(this).apply {
            text = "MOUSE"
            textSize = 11f
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_tertiary))
            letterSpacing = 0f
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 20 }
        }
        dialogView.addView(mouseLabel)

        val speedLabel = TextView(this).apply {
            text = "Trackpad speed"
            textSize = 14f
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_primary))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 14 }
        }
        dialogView.addView(speedLabel)

        val speedSlider = Slider(this).apply {
            valueFrom = 1f
            valueTo = 10f
            stepSize = 1f
            value = MousePrefs.getSpeed(this@MainActivity).toFloat()
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 4 }
        }
        dialogView.addView(speedSlider)

        val tapToClick = CheckBox(this).apply {
            text = "Tap to click"
            textSize = 13f
            isChecked = MousePrefs.getTapToClick(this@MainActivity)
            buttonTintList = ColorStateList.valueOf(accent)
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_secondary))
        }
        dialogView.addView(tapToClick)

        val naturalScroll = CheckBox(this).apply {
            text = "Natural scrolling"
            textSize = 13f
            isChecked = MousePrefs.getNaturalScroll(this@MainActivity)
            buttonTintList = ColorStateList.valueOf(accent)
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_secondary))
        }
        dialogView.addView(naturalScroll)

        val airSensLabel = TextView(this).apply {
            text = "Air mouse sensitivity"
            textSize = 14f
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_primary))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 18 }
        }
        dialogView.addView(airSensLabel)

        val airSensSlider = Slider(this).apply {
            valueFrom = 1f
            valueTo = 10f
            stepSize = 1f
            value = MousePrefs.getAirSens(this@MainActivity).toFloat()
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = 4 }
        }
        dialogView.addView(airSensSlider)

        val airInvert = CheckBox(this).apply {
            text = "Invert air mouse direction"
            textSize = 13f
            isChecked = MousePrefs.getAirInvert(this@MainActivity)
            buttonTintList = ColorStateList.valueOf(accent)
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_secondary))
        }
        dialogView.addView(airInvert)

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
                MousePrefs.setSpeed(this, speedSlider.value.toInt())
                MousePrefs.setTapToClick(this, tapToClick.isChecked)
                MousePrefs.setNaturalScroll(this, naturalScroll.isChecked)
                MousePrefs.setAirSens(this, airSensSlider.value.toInt())
                MousePrefs.setAirInvert(this, airInvert.isChecked)

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

    private fun showCustomAccentDialog(initialHex: String, onChosen: (String) -> Unit) {
        val initial = try {
            Color.parseColor(initialHex)
        } catch (_: IllegalArgumentException) {
            ThemeManager.getAccentColor(this)
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 16, 48, 0)
        }
        val preview = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                64
            ).apply { bottomMargin = 16 }
        }
        val valueLabel = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 14f
            typeface = Typeface.MONOSPACE
            setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_primary))
        }
        content.addView(preview)
        content.addView(valueLabel)

        fun addChannel(label: String, value: Int): Slider {
            content.addView(TextView(this).apply {
                text = label
                textSize = 13f
                setTextColor(ContextCompat.getColor(this@MainActivity, R.color.text_secondary))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { topMargin = 12 }
            })
            return Slider(this).apply {
                valueFrom = 0f
                valueTo = 255f
                stepSize = 1f
                this.value = value.toFloat()
                content.addView(this)
            }
        }

        val red = addChannel("Red", Color.red(initial))
        val green = addChannel("Green", Color.green(initial))
        val blue = addChannel("Blue", Color.blue(initial))

        fun selectedColor(): Int = Color.rgb(red.value.toInt(), green.value.toInt(), blue.value.toInt())
        fun refreshPreview() {
            val color = selectedColor()
            preview.background = GradientDrawable().apply {
                cornerRadius = 16f
                setColor(color)
            }
            valueLabel.text = String.format("#%06X", 0xFFFFFF and color)
        }
        listOf(red, green, blue).forEach { slider ->
            slider.addOnChangeListener { _, _, _ -> refreshPreview() }
        }
        refreshPreview()

        val dialog = AlertDialog.Builder(this)
            .setTitle("Custom accent")
            .setView(content)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Use", null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                onChosen(String.format("#%06X", 0xFFFFFF and selectedColor()))
                dialog.dismiss()
            }
        }
        dialog.show()
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
        binding.btnSend.text = "Type"
        binding.btnSend.contentDescription = if (configured) "Type on ${profile!!.name}" else "Type"
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
                val target = ProfileManager.getActive(this@MainActivity)?.name ?: "computer"
                val label = if (mode == "clipboard") "Copied to $target clipboard" else "Typed on $target"
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

    // ── Mouse / trackpad ────────────────────────────────────────

    private fun mouseSpeed(): Float = MousePrefs.getSpeed(this) / 4f

    private fun onTrackpadTouch(event: MotionEvent): Boolean {
        val now = SystemClock.uptimeMillis()
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                binding.trackpadSurface.parent?.requestDisallowInterceptTouchEvent(true)
                lastTouchX = event.x
                lastTouchY = event.y
                tapDownTime = now
                tapDownX = event.x
                tapDownY = event.y
                lastMoveTime = now
                scrollActive = false
                smoothVx = 0f
                smoothVy = 0f
                prevSmDx = 0f
                prevSmDy = 0f
                momentumJob?.cancel()
                if (dragActive && !dragButtonDown) {
                    dragButtonDown = true
                    lifecycleScope.launch { sendControl("down", button = "left") }
                }
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.pointerCount >= 2) {
                    scrollActive = true
                    lastScrollX = (event.getX(0) + event.getX(1)) / 2f
                    lastScrollY = (event.getY(0) + event.getY(1)) / 2f
                    scrollVelX = 0f
                    scrollVelY = 0f
                    lastMoveTime = now
                    if (dragActive && dragButtonDown) {
                        dragButtonDown = false
                        lifecycleScope.launch { sendControl("up", button = "left") }
                    }
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val dt = (now - lastMoveTime).coerceIn(1L, 60L).toFloat()
                if (scrollActive && event.pointerCount >= 2) {
                    val cx = (event.getX(0) + event.getX(1)) / 2f
                    val cy = (event.getY(0) + event.getY(1)) / 2f
                    val dx = cx - lastScrollX
                    val dy = cy - lastScrollY
                    scrollVelX = 0.6f * (dx / dt * 1000f) + 0.4f * scrollVelX
                    scrollVelY = 0.6f * (dy / dt * 1000f) + 0.4f * scrollVelY
                    queueScroll(dx, dy)
                    lastScrollX = cx
                    lastScrollY = cy
                } else if (event.pointerCount == 1) {
                    val dx = event.x - lastTouchX
                    val dy = event.y - lastTouchY
                    smoothVx = 0.6f * (dx / dt * 1000f) + 0.4f * smoothVx
                    smoothVy = 0.6f * (dy / dt * 1000f) + 0.4f * smoothVy
                    queueMove(dx, dy)
                    lastTouchX = event.x
                    lastTouchY = event.y
                }
                lastMoveTime = now
            }
            MotionEvent.ACTION_POINTER_UP -> {
                if (event.pointerCount == 2) {
                    val vx = scrollVelX
                    val vy = scrollVelY
                    scrollActive = false
                    startScrollMomentum(vx, vy)
                    val remaining = if (event.actionIndex == 0) 1 else 0
                    lastTouchX = event.getX(remaining)
                    lastTouchY = event.getY(remaining)
                    lastMoveTime = now
                    smoothVx = 0f
                    smoothVy = 0f
                    prevSmDx = 0f
                    prevSmDy = 0f
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                binding.trackpadSurface.parent?.requestDisallowInterceptTouchEvent(false)
                scrollActive = false
                if (dragActive && dragButtonDown) {
                    dragButtonDown = false
                    lifecycleScope.launch { sendControl("up", button = "left") }
                } else if (event.actionMasked == MotionEvent.ACTION_UP &&
                    MousePrefs.getTapToClick(this) && !dragActive
                ) {
                    val moved = hypot(event.x - tapDownX, event.y - tapDownY)
                    val quick = now - tapDownTime < 300L
                    if (quick && moved < 12f * resources.displayMetrics.density) {
                        lifecycleScope.launch {
                            if (sendControl("click", button = "left")) {
                                vibrateLight()
                                flashMouseStatus("Tap", ok = true)
                            }
                        }
                    }
                }
                momentumJob?.cancel()
            }
        }
        return true
    }

    private fun queueMove(dx: Float, dy: Float) {
        val speed = mouseSpeed()
        val velocity = hypot(smoothVx, smoothVy)
        val norm = min(1f, velocity / 850f)
        val gain = 0.8f + 1.9f * norm * norm
        val smDx = 0.55f * dx + 0.45f * prevSmDx
        val smDy = 0.55f * dy + 0.45f * prevSmDy
        prevSmDx = smDx
        prevSmDy = smDy
        pendingMoveDx += (smDx * speed * gain).roundToInt()
        pendingMoveDy += (smDy * speed * gain).roundToInt()
        ensureMouseSender()
    }

    private fun queueScroll(dx: Float, dy: Float) {
        val speed = mouseSpeed()
        val natural = MousePrefs.getNaturalScroll(this)
        val factor = speed * 0.6f
        val outX = dx * factor
        val outY = dy * factor
        pendingScrollX += (if (natural) -outX else outX).roundToInt()
        pendingScrollY += (if (natural) -outY else outY).roundToInt()
        ensureMouseSender()
    }

    private fun startScrollMomentum(vx: Float, vy: Float) {
        if (hypot(vx, vy) < 140f) return
        momentumJob?.cancel()
        momentumJob = lifecycleScope.launch {
            var mx = vx
            var my = vy
            val speed = mouseSpeed()
            val natural = MousePrefs.getNaturalScroll(this@MainActivity)
            while (hypot(mx, my) > 45f) {
                var dx = (mx * 0.016f * speed * 0.5f).roundToInt()
                var dy = (my * 0.016f * speed * 0.5f).roundToInt()
                if (natural) {
                    dx = -dx
                    dy = -dy
                }
                if (dx == 0 && dy == 0) {
                    mx *= 0.9f
                    my *= 0.9f
                    delay(16)
                    continue
                }
                if (!sendControl("scroll", dx, dy, "left")) break
                mx *= 0.9f
                my *= 0.9f
                delay(16)
            }
        }
    }

    private fun ensureMouseSender() {
        if (mouseJob?.isActive == true) return
        mouseJob = lifecycleScope.launch {
            while (pendingMoveDx != 0 || pendingMoveDy != 0 ||
                pendingScrollX != 0 || pendingScrollY != 0
            ) {
                val moveDx = pendingMoveDx
                val moveDy = pendingMoveDy
                val scrollX = pendingScrollX
                val scrollY = pendingScrollY
                pendingMoveDx = 0
                pendingMoveDy = 0
                pendingScrollX = 0
                pendingScrollY = 0

                if (moveDx != 0 || moveDy != 0) {
                    val action = if (dragButtonDown) "drag" else "move"
                    if (!sendControl(action, moveDx, moveDy, "left")) break
                }
                if (scrollX != 0 || scrollY != 0) {
                    if (!sendControl("scroll", scrollX, scrollY, "left")) break
                }
                delay(16)
            }
            mouseJob = null
        }
    }

    private fun sendMouseButton(
        action: String,
        button: String,
        label: String,
        dx: Int = 0,
        dy: Int = 0,
    ) {
        if (activeHostPort() == null) return
        lifecycleScope.launch {
            if (sendControl(action, dx, dy, button)) {
                flashMouseStatus(label, ok = true)
            }
        }
    }

    private suspend fun sendControl(
        action: String,
        dx: Int = 0,
        dy: Int = 0,
        button: String = "left",
    ): Boolean {
        val hp = activeHostPort() ?: return false
        val result = BridgeClient.sendControl(
            hp.first, hp.second, action, dx, dy, button, activeToken()
        )
        if (!result.ok) {
            flashMouseStatus(result.message)
            vibrate()
        }
        return result.ok
    }

    private fun toggleDragMode() {
        dragActive = !dragActive
        if (!dragActive && dragButtonDown) {
            dragButtonDown = false
            lifecycleScope.launch { sendControl("up", button = "left") }
        }
        updateDragButton()
        flashMouseStatus(if (dragActive) "Drag on" else "Drag off", ok = true)
    }

    private fun toggleTrackpadPin() {
        trackpadPinned = !trackpadPinned
        binding.root.scrollLocked = trackpadPinned
        val accent = ThemeManager.getAccentColor(this)
        binding.btnPinTrackpad.setImageResource(
            if (trackpadPinned) R.drawable.ic_lock_closed else R.drawable.ic_lock_open
        )
        binding.btnPinTrackpad.imageTintList = ColorStateList.valueOf(
            if (trackpadPinned) accent
            else ContextCompat.getColor(this, R.color.text_tertiary)
        )
        flashMouseStatus(
            if (trackpadPinned) "Page scroll paused" else "Page scroll restored",
            ok = trackpadPinned
        )
        vibrateLight()
    }

    // ── Air mouse (gyroscope) ───────────────────────────────────

    private val gyroListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (!airMouseActive) return
            val now = event.timestamp
            val dtMs = if (lastGyroT != 0L) (now - lastGyroT) / 1_000_000L else 16L
            lastGyroT = now

            val wx = event.values[0]
            val wy = event.values[1]
            val dead = 0.04f
            val rawX = if (abs(wx) > dead) wx else 0f
            val rawY = if (abs(wy) > dead) wy else 0f

            val invert = if (MousePrefs.getAirInvert(this@MainActivity)) -1f else 1f
            val sens = MousePrefs.getAirSens(this@MainActivity) / 5f
            val pxPerRad = 1100f * sens * invert
            val targetVx = -rawY * pxPerRad
            val targetVy = -rawX * pxPerRad

            val alpha = 0.12f
            airVx += (targetVx - airVx) * alpha
            airVy += (targetVy - airVy) * alpha

            val dtSec = (dtMs / 1000f).coerceAtMost(0.1f)
            pendingMoveDx += (airVx * dtSec).roundToInt()
            pendingMoveDy += (airVy * dtSec).roundToInt()
            ensureMouseSender()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private fun startAirMouse() {
        if (airMouseActive) return
        val sm = getSystemService(Context.SENSOR_SERVICE) as? SensorManager ?: return
        val gyro = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        if (gyro == null) {
            Toast.makeText(this, "Gyroscope not available on this device", Toast.LENGTH_SHORT).show()
            return
        }
        sensorManager = sm
        gyroSensor = gyro
        airMouseActive = true
        lastGyroT = 0L
        airVx = 0f
        airVy = 0f
        sm.registerListener(gyroListener, gyro, SensorManager.SENSOR_DELAY_GAME)
        updateAirMouseButtonVisual(true)
        flashMouseStatus("Air mouse on", ok = true)
        vibrateLight()
    }

    private fun stopAirMouse() {
        if (!airMouseActive) return
        airMouseActive = false
        sensorManager?.unregisterListener(gyroListener)
        sensorManager = null
        gyroSensor = null
        updateAirMouseButtonVisual(false)
        flashMouseStatus("Air mouse off", ok = true)
    }

    private fun updateAirMouseButtonVisual(active: Boolean) {
        val btn = binding.btnAirMouse
        val accent = ThemeManager.getAccentColor(this)
        if (active) {
            btn.setBackgroundColor(ThemeManager.getAccentSoft(this))
            btn.setTextColor(accent)
            btn.strokeColor = ColorStateList.valueOf(accent)
        } else {
            btn.setBackgroundColor(ContextCompat.getColor(this, R.color.card_bg))
            btn.setTextColor(ContextCompat.getColor(this, R.color.text_primary))
            btn.strokeColor = ContextCompat.getColorStateList(this, R.color.border)
        }
    }

    private fun updateDragButton() {
        val btn = binding.btnMouseDrag
        val accent = ThemeManager.getAccentColor(this)
        if (dragActive) {
            btn.setBackgroundColor(ThemeManager.getAccentSoft(this))
            btn.setTextColor(accent)
            btn.strokeColor = ColorStateList.valueOf(accent)
        } else {
            btn.setBackgroundColor(ContextCompat.getColor(this, R.color.card_bg))
            btn.setTextColor(ContextCompat.getColor(this, R.color.text_primary))
            btn.strokeColor = ContextCompat.getColorStateList(this, R.color.border)
        }
    }

    private fun flashMouseStatus(text: String, ok: Boolean = false) {
        binding.mouseStatus.text = text
        binding.mouseStatus.setTextColor(
            ContextCompat.getColor(
                this,
                if (ok) R.color.status_ok else R.color.status_err
            )
        )
        binding.mouseStatus.visibility = View.VISIBLE
        mouseStatusJob?.cancel()
        mouseStatusJob = lifecycleScope.launch {
            delay(2200)
            binding.mouseStatus.visibility = View.GONE
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

        val targetName = Pairing.labelFor(parsed.host, parsed.name)
        AlertDialog.Builder(this)
            .setTitle("Pair with $targetName?")
            .setMessage(
                parsed.host + ":" + parsed.port + "\n\n" +
                "Everything you dictate will be sent to this address. " +
                "Only continue if you opened this link yourself."
            )
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Pair") { _, _ ->
                ProfileManager.add(
                    this,
                    ProfileManager.Profile(targetName, parsed.host, parsed.port, parsed.token)
                )
                refreshProfileChips()
                updateStatusView()
                vibrate()
            }
            .show()
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

    private fun vibrateLight() {
        try {
            val effect = VibrationEffect.createOneShot(12, 70)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(effect)
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                v.vibrate(effect)
            }
        } catch (_: Exception) {}
    }
}
