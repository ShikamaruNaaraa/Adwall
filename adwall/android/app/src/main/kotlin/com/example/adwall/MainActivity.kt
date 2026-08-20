package com.example.adwall

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val settingsChannel = "adwall/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        requestNotificationPermissionIfNeeded()
        requestOverlayPermissionIfNeeded()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(BootPrefs.FILE, Context.MODE_PRIVATE)
                when (call.method) {
                    "getLaunchOnBoot" -> {
                        result.success(prefs.getBoolean(BootPrefs.KEY_LAUNCH_ON_BOOT, true))
                    }
                    "setLaunchOnBoot" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        prefs.edit().putBoolean(BootPrefs.KEY_LAUNCH_ON_BOOT, enabled).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The boot-launch notification (see BootReceiver, tv flavor) needs this
    // granted ahead of time - it can't be requested from a BroadcastReceiver
    // at boot, so it's requested here on ordinary app launch instead.
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1001
            )
        }
    }

    // "Draw over other apps" is the BAL exemption that lets BootLaunchService
    // (tv flavor) start MainActivity from a background/foreground-service
    // context at boot. It can't be requested from a BroadcastReceiver or
    // Service, so it's requested here on ordinary app launch instead.
    private fun requestOverlayPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (!Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }
}


