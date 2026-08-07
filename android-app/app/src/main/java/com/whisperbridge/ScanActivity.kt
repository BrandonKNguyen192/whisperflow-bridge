package com.whisperbridge

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.zxing.integration.android.IntentIntegrator

/**
 * Full-screen QR scanner (ZXing). Requests the CAMERA permission at runtime
 * (required on Android 6+), then shows the capture UI. On a successful scan it
 * parses the pairing payload, saves to ProfileManager, and returns RESULT_OK so
 * MainActivity refreshes its fields. No layout — the ZXing capture UI is shown.
 */
class ScanActivity : AppCompatActivity() {

    private val cameraReq = 2001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            startScan()
        } else {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.CAMERA), cameraReq
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == cameraReq) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startScan()
            } else {
                setResult(RESULT_CANCELED); finish()
            }
        }
    }

    private fun startScan() {
        IntentIntegrator(this).apply {
            setOrientationLocked(false)
            setPrompt("Scan the pairing QR shown on your Mac console")
            setBeepEnabled(true)
            setBarcodeImageEnabled(false)
            initiateScan()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val res = IntentIntegrator.parseActivityResult(requestCode, resultCode, data)
        val parsed = res?.contents?.let { Pairing.parse(it) }
        if (parsed != null) {
            // Add scanned host as a new profile, or update existing one with same host
            val name = Pairing.labelFor(parsed.host)
            val profiles = ProfileManager.getAll(this)
            val existingIdx = profiles.indexOfFirst { it.host == parsed.host }
            if (existingIdx >= 0) {
                ProfileManager.update(this, existingIdx,
                    ProfileManager.Profile(name, parsed.host, parsed.port, parsed.token))
                ProfileManager.setActiveIndex(this, existingIdx)
            } else {
                ProfileManager.add(this, ProfileManager.Profile(name, parsed.host, parsed.port, parsed.token))
            }
            setResult(RESULT_OK)
        } else {
            setResult(RESULT_CANCELED)
        }
        finish()
    }
}
