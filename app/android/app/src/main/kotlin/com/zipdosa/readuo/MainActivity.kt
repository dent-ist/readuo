package com.zipdosa.readuo

import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.net.Uri
import android.provider.Settings
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var inviteChannel: MethodChannel? = null
    private var pendingInvite: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_VIEW) {
            pendingInvite = intent.dataString
            inviteChannel?.invokeMethod("openInvite", pendingInvite)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("readuo_social", "Friends and conversations", NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = "Friend requests, acceptances, likes and comments"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zipdosa.readuo/connectivity").setStreamHandler(object : EventChannel.StreamHandler {
            private val manager = getSystemService(ConnectivityManager::class.java)
            private var callback: ConnectivityManager.NetworkCallback? = null
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                fun emit() {
                    runOnUiThread {
                        val available = manager.getNetworkCapabilities(manager.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
                        events.success(available)
                    }
                }
                callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) { emit() }
                    override fun onLost(network: Network) { emit() }
                    override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) { emit() }
                }
                manager.registerDefaultNetworkCallback(callback!!)
                emit()
            }
            override fun onCancel(arguments: Any?) {
                callback?.let { manager.unregisterNetworkCallback(it) }
                callback = null
            }
        })
        pendingInvite = if (intent.action == Intent.ACTION_VIEW) intent.dataString else null
        inviteChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.zipdosa.readuo/invites",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "initialInvite") {
                    result.success(pendingInvite)
                    pendingInvite = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.zipdosa.readuo/settings",
        ).setMethodCallHandler { call, result ->
            if (call.method == "networkAvailable") {
                val manager = getSystemService(ConnectivityManager::class.java)
                result.success(manager.getNetworkCapabilities(manager.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)
                return@setMethodCallHandler
            }
            if (call.method == "clearPrivateCache") {
                val files = cacheDir.listFiles()
                val cleared = files != null && files.map { it.deleteRecursively() }.all { it }
                if (cleared) result.success(true)
                else result.error("cleanup-failed", "Private image cache could not be cleared.", null)
                return@setMethodCallHandler
            }
            if (call.method != "openAppSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null),
                ),
            )
            result.success(null)
        }
    }
}
