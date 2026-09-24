package com.huawei.ai.bridge

import android.content.Context
import android.content.SharedPreferences

/**
 * PrefsManager - zentrale Config, erweiterbar
 * Speichert Pi URL, Watch Fingerprint etc.
 * Battery: kein ständiges I/O, nur bei Änderung
 */
class PrefsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("ai_bridge_prefs", Context.MODE_PRIVATE)

    var piBaseUrl: String
        get() = prefs.getString("pi_url", "http://192.168.1.50:8000") ?: "http://192.168.1.50:8000"
        set(value) = prefs.edit().putString("pi_url", value.trim().removeSuffix("/")).apply()

    var watchPackage: String
        get() = prefs.getString("watch_pkg", "com.huawei.ai.watch") ?: "com.huawei.ai.watch"
        set(value) = prefs.edit().putString("watch_pkg", value).apply()

    var watchFingerprint: String
        get() = prefs.getString("watch_fp", "") ?: ""
        set(value) = prefs.edit().putString("watch_fp", value).apply()

    var lastConnectedDeviceName: String
        get() = prefs.getString("last_device_name", "") ?: ""
        set(value) = prefs.edit().putString("last_device_name", value).apply()

    // Future extensibility: feature flags
    var enableThinking: Boolean
        get() = prefs.getBoolean("enable_thinking", false)
        set(value) = prefs.edit().putBoolean("enable_thinking", value).apply()

    var enableSearch: Boolean
        get() = prefs.getBoolean("enable_search", false)
        set(value) = prefs.edit().putBoolean("enable_search", value).apply()

    var maxResponseLength: Int
        get() = prefs.getInt("max_response_len", 800)
        set(value) = prefs.edit().putInt("max_response_len", value).apply()
}
