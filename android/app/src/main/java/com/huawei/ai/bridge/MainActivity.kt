package com.huawei.ai.bridge

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.huawei.hmf.tasks.Task
import com.huawei.wearengine.HiWear
import com.huawei.wearengine.auth.AuthCallback
import com.huawei.wearengine.auth.AuthClient
import com.huawei.wearengine.auth.Permission
import com.huawei.wearengine.device.Device
import com.huawei.wearengine.device.DeviceClient
import com.huawei.wearengine.p2p.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * MainActivity - Vollständig implementiert
 * - Pi URL editierbar + speichern
 * - WearEngine Auth + Device Discovery
 * - Pi Verbindung testen
 * - Logs anzeigen
 * - Battery optimized
 */
class MainActivity : AppCompatActivity() {

    private val TAG = "AIBridge-Main"
    private lateinit var authClient: AuthClient
    private lateinit var deviceClient: DeviceClient
    private lateinit var p2pClient: P2pClient
    private lateinit var prefs: PrefsManager

    private lateinit var tvStatus: TextView
    private lateinit var etPiUrl: EditText
    private lateinit var tvLog: TextView

    private var connectedDevice: Device? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        prefs = PrefsManager(this)

        tvStatus = findViewById(R.id.tvStatus)
        etPiUrl = findViewById(R.id.etPiUrl)
        tvLog = findViewById(R.id.tvLog)

        etPiUrl.setText(prefs.piBaseUrl)

        // Init HMS
        authClient = HiWear.getAuthClient(this)
        deviceClient = HiWear.getDeviceClient(this)
        p2pClient = HiWear.getP2pClient(this)
        p2pClient.setPeerPkgName(prefs.watchPackage)
        if (prefs.watchFingerprint.isNotEmpty()) {
            p2pClient.setPeerFingerPrint(prefs.watchFingerprint)
        }

        // Permissions
        checkNotificationPermission()
        checkAndRequestPermissions()

        // Service starten
        startBridgeService()

        // UI Listeners
        findViewById<Button>(R.id.btnGetDevices)?.setOnClickListener {
            getBondedDevices()
        }
        findViewById<Button>(R.id.btnSave)?.setOnClickListener {
            val newUrl = etPiUrl.text.toString().trim()
            if (newUrl.isEmpty()) {
                Toast.makeText(this, "URL darf nicht leer sein", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            prefs.piBaseUrl = newUrl
            log("Pi URL gespeichert: $newUrl")
            Toast.makeText(this, "Gespeichert, starte Service neu", Toast.LENGTH_SHORT).show()
            startBridgeService()
        }
        findViewById<Button>(R.id.btnTestPi)?.setOnClickListener {
            testPiConnection()
        }

        log("App gestartet, Pi URL: ${prefs.piBaseUrl}")
    }

    private fun checkNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
    }

    private fun checkAndRequestPermissions() {
        val permissions = arrayOf(
            Permission.DEVICE_MANAGER,
            Permission.P2P
        )
        authClient.checkPermissions(permissions).addOnSuccessListener { result ->
            if (!result) {
                authClient.requestPermissions(permissions, object : AuthCallback {
                    override fun onOk(permissions: Array<Permission>?) {
                        Log.i(TAG, "Permissions granted")
                        log("WearEngine Permissions OK")
                        tvStatus.text = "Permissions OK, suche Uhr..."
                        getBondedDevices()
                    }
                    override fun onCancel(permissions: Array<Permission>?) {
                        Toast.makeText(this@MainActivity, "WearEngine Permission nötig", Toast.LENGTH_LONG).show()
                        tvStatus.text = "Permission verweigert!"
                        log("Permission verweigert")
                    }
                }).addOnFailureListener { e ->
                    Log.e(TAG, "Auth failed: ${e.message}")
                    tvStatus.text = "Auth Fehler: ${e.message}"
                    log("Auth Fehler: ${e.message}")
                }
            } else {
                log("Permissions bereits vorhanden")
                getBondedDevices()
            }
        }.addOnFailureListener { e ->
            log("checkPermissions Fehler: ${e.message}")
        }
    }

    private fun getBondedDevices() {
        tvStatus.text = "Suche gebundene Geräte..."
        deviceClient.bondedDevices.addOnSuccessListener { devices ->
            Log.i(TAG, "Bonded devices: ${devices.size}")
            log("Gefundene Geräte: ${devices.size}")
            if (devices.isEmpty()) {
                Toast.makeText(this, "Keine Uhr in Huawei Health gebunden", Toast.LENGTH_LONG).show()
                tvStatus.text = "Keine Uhr gebunden"
                log("Keine Geräte - Huawei Health prüfen")
                return@addOnSuccessListener
            }
            for (device in devices) {
                log("Gerät: ${device.name} UUID=${device.uuid} Connected=${device.isConnected}")
                if (device.isConnected) {
                    connectedDevice = device
                    prefs.lastConnectedDeviceName = device.name ?: ""
                    tvStatus.text = "Verbunden: ${device.name}"
                    log("Verbunden mit ${device.name}")
                    pingDevice(device)
                    break
                }
            }
            if (connectedDevice == null) {
                connectedDevice = devices[0]
                tvStatus.text = "Gerät gefunden, nicht verbunden: ${devices[0].name}"
                log("Gerät nicht verbunden: ${devices[0].name}")
            }
        }.addOnFailureListener { e ->
            Log.e(TAG, "getBondedDevices failed: ${e.message}")
            tvStatus.text = "Fehler: ${e.message}"
            log("getBondedDevices Fehler: ${e.message}")
        }
    }

    private fun pingDevice(device: Device) {
        p2pClient.ping(device) { resultCode ->
            Log.i(TAG, "Ping result: $resultCode (207=OK)")
            log("Ping result: $resultCode (207=OK)")
        }.addOnSuccessListener {
            Log.i(TAG, "Ping success")
        }.addOnFailureListener { e ->
            Log.e(TAG, "Ping failed: ${e.message}")
            log("Ping failed: ${e.message}")
        }
    }

    private fun startBridgeService() {
        val intent = Intent(this, BridgeService::class.java).apply {
            putExtra("pi_url", prefs.piBaseUrl)
            putExtra("watch_pkg", prefs.watchPackage)
            putExtra("watch_fp", prefs.watchFingerprint)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        Log.i(TAG, "BridgeService started with ${prefs.piBaseUrl}")
        log("Service gestartet: ${prefs.piBaseUrl}")
    }

    private fun testPiConnection() {
        val url = prefs.piBaseUrl.removeSuffix("/") + "/health"
        tvStatus.text = "Teste $url ..."
        log("Teste Pi: $url")

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val client = OkHttpClient.Builder()
                    .connectTimeout(5, TimeUnit.SECONDS)
                    .readTimeout(5, TimeUnit.SECONDS)
                    .build()
                val request = Request.Builder().url(url).get().build()
                val response = client.newCall(request).execute()
                val body = response.body?.string() ?: ""
                withContext(Dispatchers.Main) {
                    if (response.isSuccessful) {
                        tvStatus.text = "Pi OK: $body"
                        log("Pi Test OK: $body")
                        Toast.makeText(this@MainActivity, "Pi erreichbar!", Toast.LENGTH_SHORT).show()
                    } else {
                        tvStatus.text = "Pi Fehler ${response.code}"
                        log("Pi Test Fehler ${response.code}: $body")
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    tvStatus.text = "Pi nicht erreichbar: ${e.message}"
                    log("Pi Test Exception: ${e.message}")
                    Toast.makeText(this@MainActivity, "Pi nicht erreichbar: ${e.message}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun log(msg: String) {
        Log.i(TAG, msg)
        runOnUiThread {
            val current = tvLog.text.toString()
            val newLog = "[${System.currentTimeMillis() % 100000}] $msg\n$current"
            tvLog.text = newLog.take(2000) // limit
        }
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
