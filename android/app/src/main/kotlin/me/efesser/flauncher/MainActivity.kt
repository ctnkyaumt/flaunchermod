/*
 * FLaunchermod
 * originally by efesser (30 May 2021)
 * ctnkyaumt 2026
 * Copyright (C) 2021 Étienne Fesser
 * Copyright (C) 2026 ctnkyaumt
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher

import android.content.BroadcastReceiver
import android.content.Intent
import android.content.Intent.*
import android.content.IntentFilter
import android.content.pm.*
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.net.Uri
import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import android.provider.Settings
import android.content.Context
import androidx.annotation.NonNull
import android.media.tv.TvInputInfo
import android.media.tv.TvInputManager
import android.media.tv.TvInputManager.TvInputCallback
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodChannel
import java.io.Serializable
import java.util.concurrent.Executor

private const val PICK_BACKUP_JSON_REQUEST_CODE = 2001

class MainActivity : FlutterActivity() {
    val launcherAppsCallbacks = ArrayList<LauncherApps.Callback>()
    private var tvInputCallback: TvInputCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pickBackupJsonResult: MethodChannel.Result? = null
    private var keyCaptureReceiver: BroadcastReceiver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val systemTextInputDialog by lazy { SystemTextInputDialog(this) }

    // File and icon work runs here, one call at a time and in order; answers
    // and events go back through the main thread, where the EventSinks live.
    private val backgroundExecutor = ChannelWork.newBackgroundExecutor()
    private val channelWork = ChannelWork(backgroundExecutor, Executor { mainHandler.post(it) }) { message, error ->
        android.util.Log.e("FLauncher", message, error)
    }

    // Pairing waits on a socket; on its own thread it cannot hold up app
    // listings or package events.
    private val pairingExecutor = ChannelWork.newBackgroundExecutor()
    private val pairingWork = ChannelWork(pairingExecutor, Executor { mainHandler.post(it) }) { message, error ->
        android.util.Log.e("FLauncher", message, error)
    }

    // Each keeps the context and only touches it when called, after onCreate.
    private val appCatalog = AppCatalog(this)
    private val backupFiles = BackupFiles(this)
    private val tvInputs = TvInputs(this)
    private val apkInstaller = ApkInstaller(this)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ChannelContract.METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getApplications" -> channelWork.call(call.method, result.asReply()) { appCatalog.getApplications() }
                    "applicationExists" -> result.success(appCatalog.applicationExists(call.arguments as String))
                    "launchApp" -> result.success(launchApp(call.arguments as String))
                    "openSettings" -> result.success(openSettings())
                    "openWifiSettings" -> result.success(openWifiSettings())
                    "showSystemTextInput" -> systemTextInputDialog.show(call.arguments as Map<*, *>, result)
                    "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                    "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                    "isDefaultLauncher" -> result.success(isDefaultLauncher())
                    "isButtonMapperEnabled" -> result.success(FLauncherAccessibilityService.isEnabled(this))
                    "getMappableApplications" -> channelWork.call(call.method, result.asReply()) { appCatalog.getMappableApplications() }
                    "shizukuStatus" -> result.success(ShizukuInputBridge.status().name)
                    "requestShizukuPermission" -> result.success(requestShizukuPermission())
                    "shizukuInputDevices" -> result.success(ShizukuInputBridge.openedDevices)
                    "rawInputStatus" -> result.success(rawInputStatus())
                    "adbPair" -> {
                        val args = call.arguments as Map<*, *>
                        val port = (args["port"] as Number).toInt()
                        val code = args["code"] as String
                        // Pairing opens a socket, which Android refuses on the
                        // main thread.
                        pairingWork.call(call.method, result.asReply()) { AdbInputBridge.pair(this@MainActivity, port, code) }
                    }
                    "startRawInput" -> {
                        notifyRawInputAvailable()
                        result.success(true)
                    }
                    "openAccessibilitySettings" -> result.success(openAccessibilitySettings())
                    "notifyButtonMappingsChanged" -> result.success(notifyButtonMappingsChanged())
                    "setKeyCaptureMode" -> result.success(setKeyCaptureMode(call.arguments as Boolean))
                    "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability())
                    "startAmbientMode" -> result.success(startAmbientMode())
                    "getHdmiInputs" -> result.success(tvInputs.getHdmiInputs())
                    "getTvInputs" -> result.success(tvInputs.getTvInputs())
                    "openEngineeringMenu" -> result.success(openEngineeringMenu(call.argument<String>("menu")))
                    "launchTvInput" -> result.success(tvInputs.launchTvInput(call.argument<String>("inputId")))
                    "shutdownDevice" -> result.success(shutdownDevice())
                    "standbyDevice" -> result.success(FLauncherAccessibilityService.standbyDevice())
                    "installApk" -> {
                        val filePath = call.arguments as String
                        // The device-owner session copy runs in the background;
                        // starting the installer or settings is back on the UI thread.
                        channelWork.callThen(
                            call.method,
                            result.asReply(),
                            { apkInstaller.prepare(filePath) },
                            { step -> apkInstaller.finish(step) },
                        )
                    }
                    "canRequestPackageInstalls" -> result.success(apkInstaller.canRequestPackageInstalls())
                    "requestPackageInstallsPermission" -> result.success(apkInstaller.requestPackageInstallsPermission())
                    "requestStoragePermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            requestPermissions(arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE, android.Manifest.permission.WRITE_EXTERNAL_STORAGE), 1001)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    }
                    "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                    "requestAllFilesAccess" -> result.success(requestAllFilesAccess())
                    "saveBackupToDownloads" -> {
                        val filePath = call.arguments as String
                        channelWork.call(call.method, result.asReply()) { backupFiles.saveBackupToDownloads(filePath) }
                    }
                    "listBackupJsonInDownloads" -> channelWork.call(call.method, result.asReply()) { backupFiles.listBackupJsonInDownloads() }
                    "readContentUri" -> {
                        val uri = call.arguments as String
                        channelWork.call(call.method, result.asReply()) { backupFiles.readContentUri(uri) }
                    }
                    "pickBackupJson" -> {
                        if (pickBackupJsonResult != null) {
                            result.error("busy", "A document picker is already active", null)
                        } else {
                            pickBackupJsonResult = result
                            try {
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "*/*"
                                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/*"))
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivityForResult(intent, PICK_BACKUP_JSON_REQUEST_CODE)
                            } catch (e: Exception) {
                                pickBackupJsonResult = null
                                throw e
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "MethodChannel error (${call.method}): ${e.message}")
                result.error(ChannelWork.NATIVE_ERROR, e.message, null)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ChannelContract.EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            lateinit var launcherAppsCallback: LauncherApps.Callback
            val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
            override fun onListen(arguments: Any?, events: EventSink) {
                // Icons are encoded on the background thread; every event,
                // removals too, goes through the same queue so they reach
                // Dart in the order they happened, on the main thread.
                launcherAppsCallback = object : LauncherApps.Callback() {
                    override fun onPackageRemoved(packageName: String, user: UserHandle) {
                        channelWork.event(ChannelContract.ACTION_PACKAGE_REMOVED, {
                            mapOf(
                                ChannelContract.KEY_ACTION to ChannelContract.ACTION_PACKAGE_REMOVED,
                                ChannelContract.KEY_PACKAGE_NAME to packageName,
                            )
                        }) { events.success(it) }
                    }

                    override fun onPackageAdded(packageName: String, user: UserHandle) {
                        channelWork.event(ChannelContract.ACTION_PACKAGE_ADDED, { appCatalog.getApplication(packageName) }) { app ->
                            if (app != null) {
                                events.success(
                                    mapOf(
                                        ChannelContract.KEY_ACTION to ChannelContract.ACTION_PACKAGE_ADDED,
                                        ChannelContract.KEY_ACTIVITY_INFO to app,
                                    )
                                )
                            }
                        }
                    }

                    override fun onPackageChanged(packageName: String, user: UserHandle) {
                        channelWork.event(ChannelContract.ACTION_PACKAGE_CHANGED, { appCatalog.getApplication(packageName) }) { app ->
                            if (app != null) {
                                events.success(
                                    mapOf(
                                        ChannelContract.KEY_ACTION to ChannelContract.ACTION_PACKAGE_CHANGED,
                                        ChannelContract.KEY_ACTIVITY_INFO to app,
                                    )
                                )
                            }
                        }
                    }

                    override fun onPackagesAvailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {
                        val names = packageNames.toList()
                        // A package with nothing to launch has no entry.
                        channelWork.event(ChannelContract.ACTION_PACKAGES_AVAILABLE, { names.mapNotNull(appCatalog::getApplication) }) { applications ->
                            if (applications.isNotEmpty()) {
                                events.success(
                                    mapOf(
                                        ChannelContract.KEY_ACTION to ChannelContract.ACTION_PACKAGES_AVAILABLE,
                                        ChannelContract.KEY_ACTIVITIES_INFO to applications,
                                    )
                                )
                            }
                        }
                    }

                    override fun onPackagesUnavailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {}
                }

                launcherAppsCallbacks.add(launcherAppsCallback)
                launcherApps.registerCallback(launcherAppsCallback)
            }

            override fun onCancel(arguments: Any?) {
                launcherApps.unregisterCallback(launcherAppsCallback)
                launcherAppsCallbacks.remove(launcherAppsCallback)
            }
        })

        // Event Channel for HDMI Input changes
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ChannelContract.HDMI_EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            val tvInputManager = getSystemService(TV_INPUT_SERVICE) as TvInputManager

            override fun onListen(arguments: Any?, events: EventSink) {
                tvInputCallback = object : TvInputCallback() {
                    override fun onInputAdded(inputId: String) {
                        tvInputs.findShownTvInput(inputId)?.let { entry ->
                            events.success(
                                mapOf(
                                    ChannelContract.KEY_ACTION to ChannelContract.ACTION_INPUT_ADDED,
                                    ChannelContract.KEY_INPUT_INFO to tvInputs.entryMap(entry),
                                )
                            )
                        }
                    }

                    override fun onInputRemoved(inputId: String) {
                        // We don't know if it was HDMI, but Flutter side can check its list
                        events.success(
                            mapOf(
                                ChannelContract.KEY_ACTION to ChannelContract.ACTION_INPUT_REMOVED,
                                ChannelContract.KEY_INPUT_ID to inputId,
                            )
                        )
                    }

                    override fun onInputUpdated(inputId: String) {
                        tvInputs.findShownTvInput(inputId)?.let { entry ->
                            events.success(
                                mapOf(
                                    ChannelContract.KEY_ACTION to ChannelContract.ACTION_INPUT_UPDATED,
                                    ChannelContract.KEY_INPUT_INFO to tvInputs.entryMap(entry),
                                )
                            )
                        }
                    }

                    override fun onInputStateChanged(inputId: String, state: Int) {
                        // Could be useful later, e.g., to show if an input is active
                        tvInputs.getTvInputInfo(inputId)?.takeIf { inputInfo -> inputInfo.type == TvInputInfo.TYPE_HDMI }?.let { _ ->
                            events.success(
                                mapOf(
                                    ChannelContract.KEY_ACTION to ChannelContract.ACTION_INPUT_STATE_CHANGED,
                                    ChannelContract.KEY_INPUT_ID to inputId,
                                    ChannelContract.KEY_STATE to state,
                                )
                            )
                        }
                    }
                }
                tvInputManager.registerCallback(tvInputCallback!!, mainHandler)
            }

            override fun onCancel(arguments: Any?) {
                tvInputCallback?.let {
                    tvInputManager.unregisterCallback(it)
                    tvInputCallback = null
                }
            }
        })

        // Carries the key code of a button pressed while the mapper is in
        // "press a button to identify it" mode.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ChannelContract.KEY_CAPTURE_EVENT_CHANNEL)
            .setStreamHandler(object : StreamHandler {
                override fun onListen(arguments: Any?, events: EventSink) {
                    keyCaptureReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.action != FLauncherAccessibilityService.ACTION_KEY_CAPTURED) return
                            events.success(
                                mapOf(
                                    ChannelContract.KEY_CAPTURE_CANCELLED to intent.getBooleanExtra(
                                        FLauncherAccessibilityService.EXTRA_CAPTURE_CANCELLED, false
                                    ),
                                    ChannelContract.KEY_KEY_CODE to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_KEY_CODE, -1
                                    ),
                                    // Without this the buttons that report
                                    // KEYCODE_UNKNOWN are indistinguishable.
                                    ChannelContract.KEY_SCAN_CODE to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_SCAN_CODE, 0
                                    ),
                                    ChannelContract.KEY_KEY_LABEL to intent.getStringExtra(
                                        FLauncherAccessibilityService.EXTRA_KEY_LABEL
                                    ),
                                    ChannelContract.KEY_KEY_ACTION to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_KEY_ACTION, -1
                                    ),
                                    ChannelContract.KEY_DEVICE to intent.getStringExtra(
                                        FLauncherAccessibilityService.EXTRA_DEVICE
                                    ),
                                    ChannelContract.KEY_RAW_CODE to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_RAW_CODE, -1
                                    ),
                                    ChannelContract.KEY_RAW_SCAN_CODE to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_RAW_SCAN_CODE, 0
                                    ),
                                )
                            )
                        }
                    }
                    val filter = IntentFilter(FLauncherAccessibilityService.ACTION_KEY_CAPTURED)
                    InternalBroadcasts.register(this@MainActivity, keyCaptureReceiver!!, filter)
                }

                override fun onCancel(arguments: Any?) {
                    unregisterKeyCaptureReceiver()
                }
            })

        // Tells Dart when a network comes up, so anything waiting on the
        // internet can retry at once instead of on its own timer.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ChannelContract.NETWORK_EVENT_CHANNEL)
            .setStreamHandler(object : StreamHandler {
                override fun onListen(arguments: Any?, events: EventSink) {
                    unregisterNetworkCallback()
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        // Only touched on the connectivity thread.
                        private val validated = HashSet<Network>()

                        override fun onAvailable(network: Network) {
                            mainHandler.post { events.success(true) }
                        }

                        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                            val usable = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                            if (!usable) {
                                validated.remove(network)
                            } else if (validated.add(network)) {
                                // Signal strength changes arrive here too; only
                                // the step to "reaches the internet" matters.
                                mainHandler.post { events.success(true) }
                            }
                        }

                        override fun onLost(network: Network) {
                            validated.remove(network)
                        }
                    }
                    try {
                        (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager)
                            .registerDefaultNetworkCallback(callback)
                        networkCallback = callback
                    } catch (e: Exception) {
                        android.util.Log.w("FLauncher", "Network callback unavailable: ${e.message}")
                    }
                }

                override fun onCancel(arguments: Any?) {
                    unregisterNetworkCallback()
                }
            })
    }

    /** Lets [ChannelWork] answer a Flutter call without knowing Flutter. */
    private fun MethodChannel.Result.asReply(): ChannelReply {
        val result = this
        return object : ChannelReply {
            override fun success(value: Any?) {
                result.success(value)
            }

            override fun error(code: String, message: String?) {
                result.error(code, message, null)
            }
        }
    }

    private fun unregisterKeyCaptureReceiver() {
        keyCaptureReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Already unregistered.
            }
            keyCaptureReceiver = null
        }
    }

    private fun unregisterNetworkCallback() {
        networkCallback?.let {
            try {
                (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it)
            } catch (e: Exception) {
                // Already unregistered.
            }
            networkCallback = null
        }
    }

    /**
     * Opens whichever accessibility screen this device actually has.
     *
     * `ACTION_ACCESSIBILITY_SETTINGS` is missing on plenty of TV boxes, whose
     * settings app is a cut-down build, so fall back to the Android TV activity
     * by name and finally to the settings root rather than doing nothing.
     */
    private fun openAccessibilitySettings(): Boolean {
        val candidates = listOf(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
            Intent(Intent.ACTION_MAIN).setComponent(
                ComponentName(
                    "com.android.tv.settings",
                    "com.android.tv.settings.system.AccessibilitySettingsActivity",
                )
            ),
            Intent(Intent.ACTION_MAIN).setComponent(
                ComponentName(
                    "com.android.tv.settings",
                    "com.android.tv.settings.accessibility.AccessibilityActivity",
                )
            ),
            Intent(Settings.ACTION_SETTINGS).setComponent(
                ComponentName("com.android.tv.settings", "com.android.tv.settings.MainSettings")
            ),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in candidates) {
            try {
                val activity = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
                    ?.activityInfo ?: continue
                // Google TV's placeholder starts successfully, then shows a
                // no-handler toast. It must not stop the real settings fallback.
                if (activity.packageName == "com.google.android.tv.frameworkpackagestubs") continue
                intent.component = ComponentName(activity.packageName, activity.name)
                startActivity(intent.addFlags(FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: Exception) {
                // Not present on this device; try the next one.
            }
        }
        return false
    }

    /**
     * Asks Shizuku for permission, and tells the accessibility service to pick
     * up the raw input helper once it has been granted.
     */
    private fun requestShizukuPermission(): Boolean {
        val granted = ShizukuInputBridge.requestPermission()
        if (granted) notifyRawInputAvailable()
        return granted
    }

    /** One picture of both routes to shell privilege, for the settings page. */
    private fun rawInputStatus(): Map<String, Serializable?> = mapOf(
        "shizuku" to ShizukuInputBridge.status().name,
        "shizukuConnected" to ShizukuInputBridge.connected,
        "adb" to AdbInputBridge.state.name,
        "adbError" to AdbInputBridge.lastError,
        "pairingRequired" to AdbInputBridge.pairingSupported,
        "devices" to ArrayList(ShizukuInputBridge.openedDevices),
    )

    private fun notifyRawInputAvailable() {
        sendBroadcast(
            Intent(FLauncherAccessibilityService.ACTION_REBIND_RAW_INPUT).setPackage(packageName)
        )
    }

    /** Tells the running accessibility service to re-read the mapping table. */
    private fun notifyButtonMappingsChanged(): Boolean {
        sendBroadcast(
            Intent(FLauncherAccessibilityService.ACTION_RELOAD_MAPPINGS).setPackage(packageName)
        )
        return true
    }

    private fun setKeyCaptureMode(enabled: Boolean): Boolean {
        sendBroadcast(
            Intent(FLauncherAccessibilityService.ACTION_SET_CAPTURE_MODE)
                .setPackage(packageName)
                .putExtra(FLauncherAccessibilityService.EXTRA_CAPTURE_ENABLED, enabled)
        )
        return true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PICK_BACKUP_JSON_REQUEST_CODE) {
            val pending = pickBackupJsonResult
            pickBackupJsonResult = null

            if (pending != null) {
                if (resultCode != Activity.RESULT_OK) {
                    pending.success(null)
                    return
                }

                val uri = data?.data
                if (uri == null) {
                    pending.success(null)
                    return
                }

                channelWork.call("pickBackupJson", pending.asReply(), errorCode = "read_error") {
                    backupFiles.readPickedDocument(uri)
                }
            }
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun hasAllFilesAccess(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Environment.isExternalStorageManager()
            } else {
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun requestAllFilesAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return true
        }

        val uri = Uri.parse("package:$packageName")
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, uri)
            startActivity(intent)
            return true
        } catch (_: Exception) {
        }

        try {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
            return true
        } catch (_: Exception) {
        }

        return try {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Shizuku answers a permission request on its own listener rather than
     * through onRequestPermissionsResult.
     */
    private val shizukuPermissionListener =
        rikka.shizuku.Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode == ShizukuInputBridge.PERMISSION_REQUEST_CODE &&
                grantResult == PackageManager.PERMISSION_GRANTED
            ) {
                notifyRawInputAvailable()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            rikka.shizuku.Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)
        } catch (e: Exception) {
            // Shizuku is optional; without it the raw input path stays off.
        }
    }

    override fun onStop() {
        systemTextInputDialog.cancel()
        super.onStop()
    }

    override fun onDestroy() {
        // Work still queued or running is dropped, and nothing answers late.
        channelWork.close()
        backgroundExecutor.shutdownNow()
        pairingWork.close()
        pairingExecutor.shutdownNow()
        apkInstaller.release()
        systemTextInputDialog.cancel()
        try {
            rikka.shizuku.Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener)
        } catch (e: Exception) {
            // Never registered.
        }
        val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
        launcherAppsCallbacks.forEach(launcherApps::unregisterCallback)
        tvInputCallback?.let {
            val tvInputManager = getSystemService(TV_INPUT_SERVICE) as TvInputManager
            tvInputManager.unregisterCallback(it)
        }
        unregisterKeyCaptureReceiver()
        unregisterNetworkCallback()
        super.onDestroy()
    }

    private fun launchApp(packageName: String) = try {
        val intent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
                ?: packageManager.getLaunchIntentForPackage(packageName)
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun openSettings() = try {
        startActivity(Intent(Settings.ACTION_SETTINGS))
        true
    } catch (e: Exception) {
        false
    }

    private fun openWifiSettings() = try {
        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
        true
    } catch (e: Exception) {
        false
    }

    private fun openAppInfo(packageName: String) = try {
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun uninstallApp(packageName: String) = try {
        Intent(ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun checkForGetContentAvailability() = try {
        val intentActivities = packageManager.queryIntentActivities(Intent(ACTION_GET_CONTENT, null).setTypeAndNormalize("image/*"), 0)
        intentActivities.isNotEmpty()
    } catch (e: Exception) {
        false
    }

    private fun isDefaultLauncher() = try {
        val defaultLauncher = packageManager.resolveActivity(Intent(ACTION_MAIN).addCategory(CATEGORY_HOME), 0)
        defaultLauncher?.activityInfo?.packageName == packageName
    } catch (e: Exception) {
        false
    }

    private fun startAmbientMode() = try {
        Intent(ACTION_MAIN)
            .setClassName("com.android.systemui", "com.android.systemui.Somnambulator")
            .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    /** Opens the MediaTek factory "Design Menu" or "Factory Menu" through its public activity. */
    private fun openEngineeringMenu(menu: String?): Boolean {
        val (component, action) = when (menu) {
            "design" -> ComponentName(
                "mediatek.factorymenu.ui",
                "mediatek.tvsetting.factory.ui.designmenu.DesignMenuActivity"
            ) to "mediatek.tvsetting.factory.intent.action.MainmenuActivity"
            "factory" -> ComponentName(
                "mediatek.factorymenu.ui",
                "mediatek.tvsetting.factory.ui.factorymenu.FactoryMenuActivity"
            ) to "mediatek.tvsetting.factory.intent.action.FactorymenuActivity"
            else -> return false
        }
        val attempts = listOf(
            Intent().setComponent(component),
            Intent(action),
        )
        for (intent in attempts) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                android.util.Log.w("FLauncher", "Engineering menu $menu unavailable via $intent: ${e.message}")
            } catch (e: SecurityException) {
                android.util.Log.w("FLauncher", "Engineering menu $menu not permitted via $intent: ${e.message}")
            }
        }
        return false
    }

    /** Opens supported system-owned power UI; never guesses low-level commands. */
    private fun shutdownDevice(): Boolean {
        // Ordinary launchers cannot hold SHUTDOWN. A system-installed launcher
        // may use the platform confirmation; otherwise the accessibility API
        // opens the same power menu as a long press of the remote power button.
        if (checkSelfPermission("android.permission.SHUTDOWN") == PackageManager.PERMISSION_GRANTED) {
            try {
                val intent = Intent("com.android.internal.intent.action.REQUEST_SHUTDOWN")
                intent.putExtra("android.intent.extra.KEY_CONFIRM", true)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "System shutdown confirmation unavailable", e)
            }
        }
        return FLauncherAccessibilityService.showPowerDialog()
    }
}
