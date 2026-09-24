package com.huawei.ai.bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.huawei.wearengine.HiWear
import com.huawei.wearengine.device.Device
import com.huawei.wearengine.device.DeviceClient
import com.huawei.wearengine.p2p.*
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

/**
 * BridgeService - Vollständig implementiert mit allen Features
 * - Chat, Weather (future), Translate, Summary
 * - Battery optimized, chunked Bluetooth
 */
class BridgeService : Service() {

    private val TAG = "AIBridge-Service"
    private val CHANNEL_ID = "ai_bridge_channel"
    private val NOTIF_ID = 1001

    private lateinit var deviceClient: DeviceClient
    private lateinit var p2pClient: P2pClient
    private lateinit var okHttpClient: OkHttpClient
    private lateinit var prefs: PrefsManager

    private var piBaseUrl: String = "http://192.168.1.50:8000"
    private var watchPkg: String = "com.huawei.ai.watch"
    private var watchFp: String = ""

    private var connectedDevice: Device? = null
    private var messageReceiver: Receiver? = null

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var lastRequestJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        prefs = PrefsManager(this)
        createNotificationChannel()
        startForeground(NOTIF_ID, createNotification("Bereit - warte auf Uhr"))

        okHttpClient = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(40, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .addInterceptor { chain ->
                val req = chain.request().newBuilder()
                    .header("Content-Type", "application/json")
                    .header("Accept", "application/json")
                    .header("Accept-Encoding", "gzip")
                    .header("User-Agent", "Huawei-AI-Bridge/1.0")
                    .build()
                chain.proceed(req)
            }
            .build()

        deviceClient = HiWear.getDeviceClient(this)
        p2pClient = HiWear.getP2pClient(this)
        Log.i(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        piBaseUrl = intent?.getStringExtra("pi_url") ?: prefs.piBaseUrl
        watchPkg = intent?.getStringExtra("watch_pkg") ?: prefs.watchPackage
        watchFp = intent?.getStringExtra("watch_fp") ?: prefs.watchFingerprint

        p2pClient.setPeerPkgName(watchPkg)
        if (watchFp.isNotEmpty()) {
            p2pClient.setPeerFingerPrint(watchFp)
        }

        Log.i(TAG, "Service started with Pi URL: $piBaseUrl")
        updateNotification("Verbinde mit Uhr...")
        fetchConnectedDeviceAndRegister()

        return START_STICKY
    }

    private fun fetchConnectedDeviceAndRegister() {
        deviceClient.bondedDevices.addOnSuccessListener { devices ->
            if (devices.isEmpty()) {
                Log.w(TAG, "No bonded devices")
                updateNotification("Keine Uhr gebunden")
                return@addOnSuccessListener
            }
            connectedDevice = devices.firstOrNull { it.isConnected } ?: devices[0]
            Log.i(TAG, "Using device: ${connectedDevice?.name}")
            updateNotification("Verbunden: ${connectedDevice?.name}")
            registerMessageReceiver()
        }.addOnFailureListener { e ->
            Log.e(TAG, "Failed to get devices: ${e.message}")
            updateNotification("Fehler: ${e.message}")
        }
    }

    private fun registerMessageReceiver() {
        messageReceiver?.let {
            try { p2pClient.unregisterReceiver(it) } catch (_: Exception) {}
        }

        messageReceiver = object : Receiver {
            override fun onSuccess() { Log.i(TAG, "Receiver registered") }
            override fun onFailure(errorCode: Int) {
                Log.e(TAG, "Receiver register failed: $errorCode")
                updateNotification("Receiver Fehler: $errorCode")
            }
            override fun onReceiveMessage(message: Message) {
                handleWatchMessage(message)
            }
        }

        p2pClient.registerReceiver(messageReceiver).addOnSuccessListener {
            Log.i(TAG, "Receiver registration success")
        }.addOnFailureListener { e ->
            Log.e(TAG, "Receiver registration failed: ${e.message}")
        }
    }

    private fun handleWatchMessage(message: Message) {
        try {
            val payloadStr = String(message.data ?: ByteArray(0), StandardCharsets.UTF_8)
            Log.i(TAG, "Received from watch: ${payloadStr.take(300)}")
            if (payloadStr.isBlank()) return

            val json = try { JSONObject(payloadStr) } catch (e: Exception) {
                JSONObject().put("prompt", payloadStr).put("type", "chat")
            }

            val type = json.optString("type", "chat")
            val prompt = json.optString("prompt", payloadStr)
            val requestId = json.optString("id", System.currentTimeMillis().toString())

            if (prompt.isBlank()) {
                sendToWatch(JSONObject().put("error", "Empty prompt").put("id", requestId).toString(), requestId)
                return
            }

            lastRequestJob?.cancel()
            lastRequestJob = serviceScope.launch {
                delay(250)
                updateNotification("[$type] ${prompt.take(30)}...")
                val result = when (type) {
                    "chat" -> callPiBackend("/api/chat", prompt, requestId, mapOf("thinking" to prefs.enableThinking, "search" to prefs.enableSearch))
                    "summarize" -> callPiBackend("/api/summarize", prompt, requestId, emptyMap())
                    "translate" -> callPiBackend("/api/translate", prompt, requestId, mapOf("target_lang" to json.optString("target_lang", "en")))
                    "weather" -> callPiBackend("/api/weather", prompt, requestId, emptyMap()) // future, fallback to chat
                    else -> callPiBackend("/api/chat", prompt, requestId, emptyMap())
                }
                sendToWatch(result, requestId)
                updateNotification("Bereit")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling watch message: ${e.message}", e)
        }
    }

    private suspend fun callPiBackend(endpoint: String, prompt: String, requestId: String, extra: Map<String, Any>): String {
        return withContext(Dispatchers.IO) {
            try {
                val trimmedPrompt = if (prompt.length > 600) prompt.take(600) else prompt

                val requestJson = JSONObject().apply {
                    put("prompt", trimmedPrompt)
                    put("history_id", "watch-$requestId")
                    put("id", requestId)
                    for ((k,v) in extra) {
                        when(v) {
                            is Boolean -> put(k, v)
                            is String -> put(k, v)
                            is Int -> put(k, v)
                        }
                    }
                }

                val body = requestJson.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder()
                    .url("$piBaseUrl$endpoint")
                    .post(body)
                    .build()

                Log.i(TAG, "Calling Pi: $piBaseUrl$endpoint")

                val response = okHttpClient.newCall(request).execute()
                val responseBody = response.body?.string() ?: ""

                if (!response.isSuccessful) {
                    Log.e(TAG, "Pi error ${response.code}: $responseBody")
                    // Fallback to chat if endpoint not exists
                    if (response.code == 404 && endpoint != "/api/chat") {
                        return@withContext callPiBackend("/api/chat", prompt, requestId, emptyMap())
                    }
                    return@withContext JSONObject().apply {
                        put("id", requestId)
                        put("error", "Pi Error ${response.code}")
                        put("response", "Fehler: $responseBody")
                    }.toString()
                }

                val piJson = JSONObject(responseBody)
                val aiResponse = piJson.optString("response", piJson.optString("result", "Keine Antwort"))
                val thinking = piJson.optString("thinking", "")
                val truncated = piJson.optBoolean("truncated", false)

                val resultJson = JSONObject().apply {
                    put("id", requestId)
                    put("type", piJson.optString("type", "chat"))
                    put("response", aiResponse)
                    if (thinking.isNotEmpty() && thinking.length < 500) put("thinking", thinking)
                    put("truncated", truncated)
                    put("took_ms", piJson.optInt("took_ms", 0))
                }
                Log.i(TAG, "Pi success: ${aiResponse.take(100)}")
                return@withContext resultJson.toString()

            } catch (e: IOException) {
                Log.e(TAG, "Network error: ${e.message}", e)
                return@withContext JSONObject().apply {
                    put("id", requestId)
                    put("error", "network")
                    put("response", "Pi nicht erreichbar (${e.message}). IP: $piBaseUrl")
                }.toString()
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected: ${e.message}", e)
                return@withContext JSONObject().apply {
                    put("id", requestId)
                    put("error", "internal")
                    put("response", "Fehler: ${e.message}")
                }.toString()
            }
        }
    }

    private fun sendToWatch(payload: String, requestId: String) {
        val device = connectedDevice ?: return
        val MAX_CHUNK = 800
        val bytes = payload.toByteArray(StandardCharsets.UTF_8)

        if (bytes.size <= MAX_CHUNK) {
            sendSingleMessage(device, payload, requestId)
        } else {
            Log.i(TAG, "Chunking ${bytes.size} bytes")
            val chunks = bytes.toList().chunked(MAX_CHUNK)
            chunks.forEachIndexed { idx, chunk ->
                val chunkStr = JSONObject().apply {
                    put("id", requestId)
                    put("chunk_index", idx)
                    put("chunk_total", chunks.size)
                    put("chunk_data", String(chunk.toByteArray(), StandardCharsets.UTF_8))
                    put("is_chunked", true)
                }.toString()
                sendSingleMessage(device, chunkStr, "$requestId-$idx")
                Thread.sleep(80)
            }
        }
    }

    private fun sendSingleMessage(device: Device, payload: String, requestId: String) {
        val message = Message.Builder().setPayload(payload.toByteArray(StandardCharsets.UTF_8)).build()
        p2pClient.send(device, message, object : SendCallback {
            override fun onSendResult(resultCode: Int) {
                Log.i(TAG, "Send result $requestId: $resultCode")
            }
            override fun onSendProgress(progress: Long) {}
        }).addOnSuccessListener {
            Log.i(TAG, "Send success $requestId")
        }.addOnFailureListener { e ->
            Log.e(TAG, "Send failed $requestId: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "AI Bridge", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Huawei Watch AI Bridge"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun createNotification(content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AI Bridge aktiv")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(content: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, createNotification(content))
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        messageReceiver?.let { try { p2pClient.unregisterReceiver(it) } catch (_: Exception) {} }
        serviceScope.cancel()
        okHttpClient.dispatcher.executorService.shutdown()
    }
}
