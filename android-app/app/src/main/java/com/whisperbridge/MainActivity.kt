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
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
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
        ThemeManager.applyEarthPalette(binding.root)

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

        // Material Expressive entrance motion: stagger the cards so the
        // screen rises into place, grow the accent line, and give every
        // button spring-physics press feedback.
        MotionKit.revealRise(binding.composeCard, startDelay = 80L)
        MotionKit.revealRise(binding.mouseCard, startDelay = 160L)
        MotionKit.growFromStart(binding.accentLine, startDelay = 120L)
        MotionKit.installSpringPressRecursive(binding.root)
        setupTrackpadGlow()

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
        ThemeManager.applyEarthPalette(binding.root)
    }

    override fun onPause() {
        super.onPause()
        if (airMouseActive) stopAirMouse()
    }

   // ── Accent application ───────────────────────────────────────

    /** Convert dp to pixels. The old UI built LayoutParams in raw pixels,
     * which is what made chips and settings buttons look squashed. */
    private fun Int.dp(): Int = (this * resources.displayMetrics.density).roundToInt()

    private fun applyAccentToView(root: View) {
        val accent = ThemeManager.getAccentColor(this)
        applyAccentRecursive(root, accent)
    }

    private fun applyAccentRecursive(view: View, accent: Int) {
        if (view is MaterialButton) {
            val defaultAccent = ContextCompat.getColor(view.context, R.color.accent)
            if (view.backgroundTintList?.defaultColor == defaultAccent) {
                // Filled primary action (Type, Save) — recolor the fill.
                view.backgroundTintList = ColorStateList.valueOf(accent)
                view.iconTint = ColorStateList.valueOf(Color.WHITE)
                view.setTextColor(Color.WHITE)
            } else {
                // Tonal/neutral button — retint any accent-colored label or icon.
                if (view.currentTextColor == defaultAccent) view.setTextColor(accent)
                if (view.iconTint?.defaultColor == defaultAccent) {
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

    private fun refreshProfileChips(animateEntrance: Boolean = true) {
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
                minWidth = 0
                insetTop = 0
                insetBottom = 0
                setPadding(20.dp(), 0, 20.dp(), 0)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    44.dp()
                ).apply {
                    marginEnd = 8.dp()
                }
                cornerRadius = 9999
                // Tonal pill — no outline. Selection reads through fill + label color.
                if (i == activeIdx) {
                    backgroundTintList = ColorStateList.valueOf(accentSoft)
                    setTextColor(accent)
                } else {
                    backgroundTintList = ColorStateList.valueOf(
                        ThemeManager.color(this@MainActivity, R.color.chip_bg)
                    )
                    setTextColor(ThemeManager.color(this@MainActivity, R.color.text_secondary))
                }
                setOnClickListener { selectProfile(i) }
                setOnLongClickListener {
                    confirmDeleteProfile(i)
                    true
                }
            }
            MotionKit.installSpringPress(chip)
            row.addView(chip)
            if (animateEntrance) MotionKit.revealRise(chip, startDelay = 40L + i * 40L)
        }

        val addChip = MaterialButton(this).apply {
            contentDescription = "Add computer"
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            minWidth = 0
            insetTop = 0
            insetBottom = 0
            setPadding(0, 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                44.dp(),
                44.dp()
            )
            cornerRadius = 9999
            backgroundTintList = ColorStateList.valueOf(
                ThemeManager.color(this@MainActivity, R.color.chip_bg)
            )
            icon = ContextCompat.getDrawable(this@MainActivity, R.drawable.ic_add)
            iconGravity = MaterialButton.ICON_GRAVITY_TEXT_START
            iconSize = 20.dp()
            iconPadding = 0
            iconTint = ColorStateList.valueOf(accent)
            setOnClickListener { promptAddProfile() }
        }
        MotionKit.installSpringPress(addChip)
        row.addView(addChip)
        if (animateEntrance) MotionKit.revealRise(addChip, startDelay = 40L + profiles.size * 40L)
    }

   private fun selectProfile(index: Int) {
       ProfileManager.setActiveIndex(this, index)
       refreshProfileChips(animateEntrance = false)
       updateStatusView()
       vibrate()
        // Spring-pop the freshly active chip so the swap reads as a move.
        val active = binding.profileChipRow.getChildAt(index) ?: return
        MotionKit.pop(active, bouncy = true)
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

    // ── Settings sheet ───────────────────────────────────────────

    private fun showSettingsDialog() {
        val profile = ProfileManager.getActive(this)
        val accent = ThemeManager.getAccentColor(this)
        val currentMode = ThemeManager.getThemeMode(this)
        val currentAccentHex = ThemeManager.getAccentHex(this)

        val sheet = BottomSheetDialog(this)
        val root = layoutInflater.inflate(R.layout.dialog_settings, null)
        sheet.setContentView(root)

        val etHost = root.findViewById<EditText>(R.id.etHost)
        val etPort = root.findViewById<EditText>(R.id.etPort)
        val etToken = root.findViewById<EditText>(R.id.etToken)
        val btnScan = root.findViewById<MaterialButton>(R.id.btnScan)
        val btnTest = root.findViewById<MaterialButton>(R.id.btnTest)
        val btnSaveConnection = root.findViewById<MaterialButton>(R.id.btnSaveConnection)
        val tvConnStatus = root.findViewById<TextView>(R.id.tvConnectionStatus)
        val themeRow = root.findViewById<LinearLayout>(R.id.themeRow)
        val accentRow1 = root.findViewById<LinearLayout>(R.id.accentRow1)
        val accentRow2 = root.findViewById<LinearLayout>(R.id.accentRow2)
        val btnCustomAccent = root.findViewById<MaterialButton>(R.id.btnCustomAccent)
        val speedSlider = root.findViewById<Slider>(R.id.speedSlider)
        val tvSpeedValue = root.findViewById<TextView>(R.id.tvSpeedValue)
        val cbTapToClick = root.findViewById<CheckBox>(R.id.cbTapToClick)
        val cbNaturalScroll = root.findViewById<CheckBox>(R.id.cbNaturalScroll)
        val airSensSlider = root.findViewById<Slider>(R.id.airSensSlider)
        val tvAirSensValue = root.findViewById<TextView>(R.id.tvAirSensValue)
        val cbAirInvert = root.findViewById<CheckBox>(R.id.cbAirInvert)

        // Prefill current values
        etHost.setText(profile?.host ?: "")
        etPort.setText((profile?.port ?: 9877).toString())
        etToken.setText(profile?.token ?: "")
        speedSlider.value = MousePrefs.getSpeed(this).toFloat()
        tvSpeedValue.text = MousePrefs.getSpeed(this).toString()
        cbTapToClick.isChecked = MousePrefs.getTapToClick(this)
        cbNaturalScroll.isChecked = MousePrefs.getNaturalScroll(this)
        airSensSlider.value = MousePrefs.getAirSens(this).toFloat()
        tvAirSensValue.text = MousePrefs.getAirSens(this).toString()
        cbAirInvert.isChecked = MousePrefs.getAirInvert(this)

        fun showConnStatus(text: String, ok: Boolean) {
            tvConnStatus.visibility = View.VISIBLE
            tvConnStatus.setTextColor(
                ThemeManager.color(this, if (ok) R.color.status_ok else R.color.status_err)
            )
            MotionKit.swapText(tvConnStatus, text)
        }

        fun saveConnection(): Boolean {
            val host = etHost.text.toString().trim()
            val port = etPort.text.toString().trim().toIntOrNull() ?: 9877
            val token = etToken.text.toString().trim()
            val activeIdx = ProfileManager.getActiveIndex(this)
            val profiles = ProfileManager.getAll(this)
            if (activeIdx !in profiles.indices) {
                showConnStatus("Add a computer profile first", ok = false)
                return false
            }
            ProfileManager.update(
                this, activeIdx,
                profiles[activeIdx].copy(host = host, port = port, token = token)
            )
            refreshProfileChips(animateEntrance = false)
            updateStatusView()
            return true
        }

        // ── Theme mode chips ─────────────────────────────────────
        val themeModes = listOf(
            Pair("Light", ThemeManager.ThemeMode.LIGHT),
            Pair("Earth", ThemeManager.ThemeMode.EARTH),
            Pair("Dark OLED", ThemeManager.ThemeMode.DARK_OLED),
            Pair("System", ThemeManager.ThemeMode.SYSTEM)
        )
        var selectedThemeMode = currentMode

        fun restyleThemeChips() {
            for (j in 0 until themeRow.childCount) {
                val c = themeRow.getChildAt(j) as MaterialButton
                if (themeModes[j].second == selectedThemeMode) {
                    c.backgroundTintList = ColorStateList.valueOf(ThemeManager.getAccentSoft(this))
                    c.setTextColor(accent)
                } else {
                    c.backgroundTintList = ColorStateList.valueOf(
                        ThemeManager.color(this, R.color.chip_bg)
                    )
                    c.setTextColor(ThemeManager.color(this, R.color.text_secondary))
                }
            }
        }

        themeModes.forEachIndexed { idx, (label, mode) ->
            val chip = MaterialButton(this).apply {
                text = label
                textSize = 13f
                isAllCaps = false
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                textAlignment = View.TEXT_ALIGNMENT_CENTER
                minWidth = 0
                insetTop = 0
                insetBottom = 0
                setPadding(18.dp(), 0, 18.dp(), 0)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    42.dp()
                ).apply { marginEnd = 8.dp() }
                cornerRadius = 9999
                setOnClickListener {
                    selectedThemeMode = mode
                    restyleThemeChips()
                    MotionKit.pop(this)
                    vibrateLight()
                }
            }
            themeRow.addView(chip)
            MotionKit.installSpringPress(chip)
            MotionKit.revealRise(chip, startDelay = 120L + idx * 50L)
        }
        restyleThemeChips()

        // ── Accent swatches ──────────────────────────────────────
        var selectedAccentHex = currentAccentHex

        fun restyleSwatches() {
            listOf(accentRow1, accentRow2).forEach { rowLayout ->
                for (i in 0 until rowLayout.childCount) {
                    val swatch = rowLayout.getChildAt(i)
                    val hex = swatch.tag as? String ?: continue
                    val color = try { Color.parseColor(hex) } catch (_: Exception) { Color.GRAY }
                    val isSelected = hex.equals(selectedAccentHex, ignoreCase = true)
                    swatch.background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(color)
                        if (isSelected) setStroke(3.dp(), Color.WHITE)
                    }
                    swatch.foreground = if (isSelected) {
                        ContextCompat.getDrawable(this, R.drawable.ic_check)?.mutate()?.apply {
                            setTint(Color.WHITE)
                        }
                    } else null
                    swatch.foregroundGravity = Gravity.CENTER
                }
            }
        }

        ThemeManager.accentOptions.forEachIndexed { i, opt ->
            val swatch = View(this).apply {
                tag = opt.hex
                layoutParams = LinearLayout.LayoutParams(44.dp(), 44.dp()).apply {
                    marginEnd = if (i % 4 == 3) 0 else 12.dp()
                }
                setOnClickListener {
                    selectedAccentHex = opt.hex
                    restyleSwatches()
                    MotionKit.pop(this, bouncy = true)
                    vibrateLight()
                }
            }
            (if (i < 4) accentRow1 else accentRow2).addView(swatch)
            MotionKit.revealRise(swatch, startDelay = 180L + i * 30L)
        }
        restyleSwatches()

        btnCustomAccent.setOnClickListener {
            showCustomAccentDialog(selectedAccentHex) { chosenHex ->
                selectedAccentHex = chosenHex
                restyleSwatches()
                btnCustomAccent.setTextColor(Color.parseColor(chosenHex))
                btnCustomAccent.text = "Custom $chosenHex"
            }
        }

        // ── Sliders ──────────────────────────────────────────────
        speedSlider.addOnChangeListener { _, value, _ ->
            tvSpeedValue.text = value.toInt().toString()
        }
        airSensSlider.addOnChangeListener { _, value, _ ->
            tvAirSensValue.text = value.toInt().toString()
        }

        // ── Actions ──────────────────────────────────────────────
        btnScan.setOnClickListener {
            sheet.dismiss()
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
                btnTest.text = "Test"
                showConnStatus(if (result.ok) "✓ Connected" else "✗ ${result.message}", result.ok)
                if (result.ok) vibrate()
            }
        }

        btnSaveConnection.setOnClickListener {
            if (saveConnection()) {
                showConnStatus("✓ Connection saved", ok = true)
                MotionKit.successPulse(btnSaveConnection)
                vibrateLight()
            }
        }

        root.findViewById<MaterialButton>(R.id.btnPasteLink).setOnClickListener {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            val raw = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()
            val parsed = raw?.let { Pairing.parse(it) }
            if (parsed == null) {
                showConnStatus("Clipboard doesn't contain a pairing link", ok = false)
            } else {
                etHost.setText(parsed.host)
                etPort.setText(parsed.port.toString())
                etToken.setText(parsed.token)
                if (saveConnection()) {
                    showConnStatus("✓ Paired with ${parsed.host}", ok = true)
                    vibrate()
                }
            }
        }

        root.findViewById<MaterialButton>(R.id.btnCancelSettings).setOnClickListener { sheet.dismiss() }
        root.findViewById<ImageButton>(R.id.btnCloseSettings).setOnClickListener { sheet.dismiss() }

        root.findViewById<MaterialButton>(R.id.btnSaveAll).setOnClickListener {
            saveConnection()

            val needsRecreate = selectedThemeMode != currentMode || selectedAccentHex != currentAccentHex
            ThemeManager.setThemeMode(this, selectedThemeMode)
            ThemeManager.setAccentHex(this, selectedAccentHex)
            MousePrefs.setSpeed(this, speedSlider.value.toInt())
            MousePrefs.setTapToClick(this, cbTapToClick.isChecked)
            MousePrefs.setNaturalScroll(this, cbNaturalScroll.isChecked)
            MousePrefs.setAirSens(this, airSensSlider.value.toInt())
            MousePrefs.setAirInvert(this, cbAirInvert.isChecked)

            refreshProfileChips(animateEntrance = false)
            updateStatusView()
            vibrate()
            sheet.dismiss()

            if (needsRecreate) {
                ThemeManager.apply(this)
                recreate()
            }
        }

        MotionKit.installSpringPressRecursive(root)
        if (ThemeManager.isEarth(this)) {
            ThemeManager.applyEarthPalette(root)
        }

        sheet.setOnShowListener {
            val bottomSheet = sheet.findViewById<FrameLayout>(
                com.google.android.material.R.id.design_bottom_sheet
            )
            bottomSheet?.let {
                it.setBackgroundColor(ThemeManager.color(this, R.color.bg))
                val behavior = BottomSheetBehavior.from(it)
                behavior.skipCollapsed = true
                behavior.state = BottomSheetBehavior.STATE_EXPANDED
            }
        }
        sheet.show()
    }

    private fun showCustomAccentDialog(initialHex: String, onChosen: (String) -> Unit) {
        val initial = try {
            Color.parseColor(initialHex)
        } catch (_: IllegalArgumentException) {
            ThemeManager.getAccentColor(this)
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24.dp(), 8.dp(), 24.dp(), 0)
        }
        val preview = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                48.dp()
            ).apply { bottomMargin = 16.dp() }
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
       binding.statusDot.setColorFilter(ThemeManager.color(this, color))
        // M3 motion: idle status gently breathes so the user knows the app is
        // alive but waiting; connected sits solid.
        MotionKit.setBreathing(binding.statusDot, on = !configured)
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
                val button = if (mode == "clipboard") binding.btnClipboard else binding.btnSend
                MotionKit.successPulse(button)
                MotionKit.swapText(button, "✓ Sent")
                button.postDelayed({ MotionKit.swapText(button, if (mode == "clipboard") "Copy" else "Type") }, 1400L)
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

    /** Accent-colored radial glow that follows the finger on the trackpad. */
    private fun setupTrackpadGlow() {
        val accent = ThemeManager.getAccentColor(this)
        val glow = GradientDrawable().apply {
            gradientType = GradientDrawable.RADIAL_GRADIENT
            colors = intArrayOf(
                Color.argb(110, Color.red(accent), Color.green(accent), Color.blue(accent)),
                Color.TRANSPARENT
            )
            gradientRadius = 48.dp().toFloat()
        }
        binding.trackpadGlow.background = glow
    }

    private fun showTrackpadGlow(x: Float, y: Float) {
        val glow = binding.trackpadGlow
        if (glow.visibility != View.VISIBLE) {
            glow.visibility = View.VISIBLE
            glow.animate().cancel()
            glow.animate().alpha(1f).setDuration(120L).start()
        }
        glow.translationX = x - glow.width / 2f
        glow.translationY = y - glow.height / 2f
        binding.trackpadCursor.animate().cancel()
        if (binding.trackpadCursor.alpha > 0f) {
            binding.trackpadCursor.animate().alpha(0f).setDuration(150L).start()
        }
    }

    private fun hideTrackpadGlow() {
        val glow = binding.trackpadGlow
        glow.animate().cancel()
        glow.animate().alpha(0f).setDuration(220L).withEndAction {
            glow.visibility = View.GONE
        }.start()
        binding.trackpadCursor.animate().cancel()
        binding.trackpadCursor.animate().alpha(1f).setDuration(250L).start()
    }

    private fun mouseSpeed(): Float = MousePrefs.getSpeed(this) / 4f

    private fun onTrackpadTouch(event: MotionEvent): Boolean {
        val now = SystemClock.uptimeMillis()
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                binding.trackpadSurface.parent?.requestDisallowInterceptTouchEvent(true)
                showTrackpadGlow(event.x, event.y)
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
                if (event.pointerCount == 1) showTrackpadGlow(event.x, event.y)
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
                hideTrackpadGlow()
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
        flashMouseStatusAnimated(if (dragActive) "Drag on" else "Drag off", ok = true)
        MotionKit.pressPulse(binding.btnMouseDrag, ok = true)
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
            else ThemeManager.color(this, R.color.text_tertiary)
        )
       flashMouseStatus(
           if (trackpadPinned) "Page scroll paused" else "Page scroll restored",
           ok = trackpadPinned
       )
       vibrateLight()
        MotionKit.pressPulse(binding.btnPinTrackpad, ok = true)
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
            btn.backgroundTintList = ColorStateList.valueOf(ThemeManager.getAccentSoft(this))
            btn.setTextColor(accent)
        } else {
            btn.backgroundTintList = ColorStateList.valueOf(
                ThemeManager.color(this, R.color.chip_bg)
            )
            btn.setTextColor(ThemeManager.color(this, R.color.text_primary))
        }
    }

    private fun updateDragButton() {
        val btn = binding.btnMouseDrag
        val accent = ThemeManager.getAccentColor(this)
        if (dragActive) {
            btn.backgroundTintList = ColorStateList.valueOf(ThemeManager.getAccentSoft(this))
            btn.setTextColor(accent)
            btn.iconTint = ColorStateList.valueOf(accent)
        } else {
            btn.backgroundTintList = ColorStateList.valueOf(
                ThemeManager.color(this, R.color.chip_bg)
            )
            btn.setTextColor(ThemeManager.color(this, R.color.text_primary))
            btn.iconTint = ColorStateList.valueOf(ThemeManager.color(this, R.color.text_primary))
        }
    }

   private fun flashMouseStatus(text: String, ok: Boolean = false) {
       binding.mouseStatus.text = text
       binding.mouseStatus.setTextColor(
           ThemeManager.color(this, if (ok) R.color.status_ok else R.color.status_err)
       )
       binding.mouseStatus.visibility = View.VISIBLE
       mouseStatusJob?.cancel()
       mouseStatusJob = lifecycleScope.launch {
           delay(2200)
           binding.mouseStatus.visibility = View.GONE
       }
   }
    private fun flashMouseStatusAnimated(text: String, ok: Boolean = false) {
        binding.mouseStatus.text = text
        binding.mouseStatus.setTextColor(
            ThemeManager.color(this, if (ok) R.color.status_ok else R.color.status_err)
        )
        binding.mouseStatus.alpha = 0f
        binding.mouseStatus.visibility = View.VISIBLE
        binding.mouseStatus.animate()
            .alpha(1f)
            .setDuration(MotionKit.DUR_SHORT_4)
            .setStartDelay(0)
            .withLayer()
            .start()
        mouseStatusJob?.cancel()
        mouseStatusJob = lifecycleScope.launch {
            delay(2000)
            MotionKit.fadeOut(binding.mouseStatus, onEnd = {
                binding.mouseStatus.visibility = View.GONE
            })
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
