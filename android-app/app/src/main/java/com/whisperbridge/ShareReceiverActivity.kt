package com.whisperbridge

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.whisperbridge.databinding.ActivityShareReceiverBinding
import kotlinx.coroutines.launch

class ShareReceiverActivity : AppCompatActivity() {

    private lateinit var binding: ActivityShareReceiverBinding
    private var sharedText: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.apply(this)
        super.onCreate(savedInstanceState)
        binding = ActivityShareReceiverBinding.inflate(layoutInflater)
        setContentView(binding.root)

        applyAccentToView(binding.root)
        ThemeManager.applyEarthPalette(binding.root)
        ThemeManager.setupAmbient(binding.ambientLayer)

        // Expressive entrance + spring press physics on every button.
        MotionKit.revealRise(binding.shareCard, startDelay = 60L)
        MotionKit.growFromStart(binding.accentLine, startDelay = 200L)
        MotionKit.installSpringPressRecursive(binding.root)

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
        binding.btnEnter.setOnClickListener { forward("enter") }
    }

    private fun applyAccentToView(root: View) {
        val accent = ThemeManager.getAccentColor(this)
        applyAccentRecursive(root, accent)
    }

    private fun applyAccentRecursive(view: View, accent: Int) {
        if (view is MaterialButton) {
            val defaultAccent = ContextCompat.getColor(view.context, R.color.accent)
            if (view.backgroundTintList?.defaultColor == defaultAccent) {
                // Filled primary action (Type) — recolor the fill.
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

    private fun forward(mode: String) {
        val profile = ProfileManager.getActive(this)
        if (profile == null || profile.host.isEmpty()) {
            binding.tvStatus.text = "No computer configured — open the app first"
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
            val textToSend = if (mode == "enter") "" else sharedText
            val result = BridgeClient.sendText(
                profile.host, profile.port, textToSend, mode, "whisperflow-share", profile.token,
                enterAfter = mode != "enter" && binding.cbEnterAfter.isChecked
            )
            binding.progress.visibility = View.GONE
            if (result.ok) {
                vibrate()
                val sentButton = when (mode) {
                    "enter" -> binding.btnEnter
                    "clipboard" -> binding.btnClipboard
                    else -> binding.btnSend
                }
                MotionKit.successPulse(sentButton)
                val target = profile.name
                val label = if (mode == "enter") "Return key sent" else
                    if (mode == "clipboard") "Copied to $target clipboard" else "Typed on $target"
                binding.tvStatus.text = label
                binding.tvStatus.setTextColor(
                    ContextCompat.getColor(this@ShareReceiverActivity, R.color.status_ok)
                )
                binding.root.postDelayed({ finish() }, 1200)
            } else {
                binding.tvStatus.text = "${result.message}"
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
