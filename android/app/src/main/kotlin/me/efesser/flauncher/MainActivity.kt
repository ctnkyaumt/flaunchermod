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
import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import android.provider.MediaStore
import android.provider.Settings
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.pm.PackageInstaller
import androidx.annotation.NonNull
import android.media.tv.TvInputInfo
import android.media.tv.TvInputManager
import android.media.tv.TvInputManager.TvInputCallback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.File
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream
import java.io.Serializable
import java.nio.ByteBuffer

private const val METHOD_CHANNEL = "me.efesser.flauncher/method"
private const val EVENT_CHANNEL = "me.efesser.flauncher/event"
private const val HDMI_EVENT_CHANNEL = "me.efesser.flauncher/hdmi_event"
private const val KEY_CAPTURE_EVENT_CHANNEL = "me.efesser.flauncher/key_capture_event"
private const val PICK_BACKUP_JSON_REQUEST_CODE = 2001
private const val MAX_BACKUP_JSON_BYTES = 32 * 1024 * 1024

class MainActivity : FlutterActivity() {
    val launcherAppsCallbacks = ArrayList<LauncherApps.Callback>()
    private var tvInputCallback: TvInputCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pickBackupJsonResult: MethodChannel.Result? = null
    private var keyCaptureReceiver: BroadcastReceiver? = null
    private val systemTextInputDialog by lazy { SystemTextInputDialog(this) }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getApplications" -> result.success(getApplications())
                    "applicationExists" -> result.success(applicationExists(call.arguments as String))
                    "launchApp" -> result.success(launchApp(call.arguments as String))
                    "openSettings" -> result.success(openSettings())
                    "openWifiSettings" -> result.success(openWifiSettings())
                    "showSystemTextInput" -> systemTextInputDialog.show(call.arguments as Map<*, *>, result)
                    "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                    "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                    "isDefaultLauncher" -> result.success(isDefaultLauncher())
                    "isButtonMapperEnabled" -> result.success(FLauncherAccessibilityService.isEnabled(this))
                    "getMappableApplications" -> result.success(getMappableApplications())
                    "shizukuStatus" -> result.success(ShizukuInputBridge.status().name)
                    "requestShizukuPermission" -> result.success(requestShizukuPermission())
                    "shizukuInputDevices" -> result.success(ShizukuInputBridge.openedDevices)
                    "rawInputStatus" -> result.success(rawInputStatus())
                    "adbPair" -> {
                        val args = call.arguments as Map<*, *>
                        result.success(
                            AdbInputBridge.pair(
                                this,
                                (args["port"] as Number).toInt(),
                                args["code"] as String,
                            )
                        )
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
                    "getHdmiInputs" -> result.success(getHdmiInputs())
                    "launchTvInput" -> result.success(launchTvInput(call.argument<String>("inputId")))
                    "shutdownDevice" -> result.success(shutdownDevice())
                    "standbyDevice" -> result.success(FLauncherAccessibilityService.standbyDevice())
                    "installApk" -> result.success(installApk(call.arguments as String))
                    "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
                    "requestPackageInstallsPermission" -> result.success(requestPackageInstallsPermission())
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
                    "saveBackupToDownloads" -> result.success(saveBackupToDownloads(call.arguments as String))
                    "listBackupJsonInDownloads" -> result.success(listBackupJsonInDownloads())
                    "readContentUri" -> result.success(readContentUri(call.arguments as String))
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
                    "shareFile" -> {
                        val path = call.arguments as String
                        val file = File(path)
                        if (file.exists()) {
                            val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
                            val intent = Intent(Intent.ACTION_SEND)
                            intent.type = "application/json"
                            intent.putExtra(Intent.EXTRA_STREAM, uri)
                            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(Intent.createChooser(intent, "Share Backup"))
                            result.success(true)
                        } else {
                            result.error("file_not_found", "File does not exist", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "MethodChannel error (${call.method}): ${e.message}")
                result.error("native_error", e.message, null)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            lateinit var launcherAppsCallback: LauncherApps.Callback
            val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
            override fun onListen(arguments: Any?, events: EventSink) {
                launcherAppsCallback = object : LauncherApps.Callback() {
                    override fun onPackageRemoved(packageName: String, user: UserHandle) {
                        events.success(mapOf("action" to "PACKAGE_REMOVED", "packageName" to packageName))
                    }

                    override fun onPackageAdded(packageName: String, user: UserHandle) {
                        getApplication(packageName)
                            ?.let { events.success(mapOf("action" to "PACKAGE_ADDED", "activitiyInfo" to it)) }
                    }

                    override fun onPackageChanged(packageName: String, user: UserHandle) {
                        getApplication(packageName)
                            ?.let { events.success(mapOf("action" to "PACKAGE_CHANGED", "activitiyInfo" to it)) }
                    }

                    override fun onPackagesAvailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {
                        val applications = packageNames.map(::getApplication)
                        if (applications.isNotEmpty()) {
                            events.success(mapOf("action" to "PACKAGES_AVAILABLE", "activitiesInfo" to applications))
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
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HDMI_EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            val tvInputManager = getSystemService(TV_INPUT_SERVICE) as TvInputManager

            override fun onListen(arguments: Any?, events: EventSink) {
                tvInputCallback = object : TvInputCallback() {
                    override fun onInputAdded(inputId: String) {
                        getTvInputInfo(inputId)?.takeIf { inputInfo -> inputInfo.type == TvInputInfo.TYPE_HDMI }?.let { inputInfo ->
                            events.success(mapOf("action" to "INPUT_ADDED", "inputInfo" to buildTvInputMap(inputInfo)))
                        }
                    }

                    override fun onInputRemoved(inputId: String) {
                        // We don't know if it was HDMI, but Flutter side can check its list
                        events.success(mapOf("action" to "INPUT_REMOVED", "inputId" to inputId))
                    }

                    override fun onInputUpdated(inputId: String) {
                        getTvInputInfo(inputId)?.takeIf { inputInfo -> inputInfo.type == TvInputInfo.TYPE_HDMI }?.let { inputInfo ->
                            events.success(mapOf("action" to "INPUT_UPDATED", "inputInfo" to buildTvInputMap(inputInfo)))
                        }
                    }

                    override fun onInputStateChanged(inputId: String, state: Int) {
                        // Could be useful later, e.g., to show if an input is active
                        getTvInputInfo(inputId)?.takeIf { inputInfo -> inputInfo.type == TvInputInfo.TYPE_HDMI }?.let { inputInfo ->
                            events.success(mapOf("action" to "INPUT_STATE_CHANGED", "inputId" to inputId, "state" to state))
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
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, KEY_CAPTURE_EVENT_CHANNEL)
            .setStreamHandler(object : StreamHandler {
                override fun onListen(arguments: Any?, events: EventSink) {
                    keyCaptureReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            if (intent?.action != FLauncherAccessibilityService.ACTION_KEY_CAPTURED) return
                            events.success(
                                mapOf(
                                    "captureCancelled" to intent.getBooleanExtra(
                                        FLauncherAccessibilityService.EXTRA_CAPTURE_CANCELLED, false
                                    ),
                                    "keyCode" to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_KEY_CODE, -1
                                    ),
                                    // Without this the buttons that report
                                    // KEYCODE_UNKNOWN are indistinguishable.
                                    "scanCode" to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_SCAN_CODE, 0
                                    ),
                                    "keyLabel" to intent.getStringExtra(
                                        FLauncherAccessibilityService.EXTRA_KEY_LABEL
                                    ),
                                    "keyAction" to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_KEY_ACTION, -1
                                    ),
                                    "device" to intent.getStringExtra(
                                        FLauncherAccessibilityService.EXTRA_DEVICE
                                    ),
                                    "rawCode" to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_RAW_CODE, -1
                                    ),
                                    "rawScanCode" to intent.getIntExtra(
                                        FLauncherAccessibilityService.EXTRA_RAW_SCAN_CODE, 0
                                    ),
                                )
                            )
                        }
                    }
                    val filter = IntentFilter(FLauncherAccessibilityService.ACTION_KEY_CAPTURED)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(keyCaptureReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(keyCaptureReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    keyCaptureReceiver?.let {
                        try {
                            unregisterReceiver(it)
                        } catch (e: IllegalArgumentException) {
                            // Already unregistered.
                        }
                        keyCaptureReceiver = null
                    }
                }
            })
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

                try {
                    try {
                        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) {
                        // Ignore if persistable permission isn't granted by the picker/provider
                    }

                    contentResolver.openInputStream(uri).use { input ->
                        if (input == null) {
                            pending.success(null)
                            return
                        }
                        pending.success(readBackupJson(input))
                    }
                } catch (e: Exception) {
                    pending.error("read_error", e.message, null)
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

    private fun saveBackupToDownloads(filePath: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null

        val file = File(filePath).canonicalFile
        val privateDirectory = File(applicationInfo.dataDir).canonicalFile
        require(file.path.startsWith(privateDirectory.path + File.separator) && file.isFile) {
            "Backup source must be an app-private file"
        }
        require(file.name.startsWith("flauncher_backup_") && file.name.endsWith(".json")) {
            "Invalid backup filename"
        }
        require(file.length() <= MAX_BACKUP_JSON_BYTES) { "Backup exceeds 32 MiB" }

        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IOException("Unable to create backup in Downloads")
        try {
            contentResolver.openOutputStream(uri, "w").use { output ->
                if (output == null) throw IOException("Unable to write backup in Downloads")
                FileInputStream(file).use { input -> input.copyTo(output) }
            }
            val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            if (contentResolver.update(uri, published, null, null) != 1) {
                throw IOException("Unable to publish backup in Downloads")
            }
            val displayName = contentResolver.query(
                uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: file.name
            return "${Environment.DIRECTORY_DOWNLOADS}/$displayName"
        } catch (e: Exception) {
            try {
                contentResolver.delete(uri, null, null)
            } catch (cleanupError: Exception) {
                android.util.Log.w("FLauncher", "Unable to remove incomplete backup", cleanupError)
            }
            throw e
        }
    }

    private fun listBackupJsonInDownloads(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        return try {
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATE_MODIFIED,
            )

            val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
            val selectionArgs = arrayOf("flauncher_backup_%", "%.json")
            val sortOrder = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"

            contentResolver.query(collection, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val modifiedCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol)
                    val modifiedSeconds = cursor.getLong(modifiedCol)
                    val uri = ContentUris.withAppendedId(collection, id)
                    results.add(
                        mapOf(
                            "uri" to uri.toString(),
                            "name" to name,
                            "modified" to (modifiedSeconds * 1000L),
                        )
                    )
                }
            }

            results
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun readContentUri(uriString: String): String? {
        return try {
            val uri = Uri.parse(uriString)
            contentResolver.openInputStream(uri).use { input ->
                if (input == null) return null
                readBackupJson(input)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun readBackupJson(input: InputStream): String {
        val bytes = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (bytes.size() > MAX_BACKUP_JSON_BYTES - count) {
                throw IOException("Backup exceeds 32 MiB")
            }
            bytes.write(buffer, 0, count)
        }
        return Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(bytes.toByteArray())).toString()
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
        super.onDestroy()
    }

    private fun getApplications(): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
        val nonTvActivitiesInfo = queryIntentActivities(true)
                .filter { nonTvActivityInfo -> !tvActivitiesInfo.any { tvActivityInfo -> tvActivityInfo.packageName == nonTvActivityInfo.packageName } }
        return tvActivitiesInfo.map { buildAppMap(it, false) } + nonTvActivitiesInfo.map { buildAppMap(it, true) }
    }

    private fun getApplication(packageName: String): Map<String, Serializable?>? {
        return packageManager.getLeanbackLaunchIntentForPackage(packageName)
            ?.resolveActivityInfo(packageManager, 0)
            ?.let { buildAppMap(it, false) }
            ?: return packageManager.getLaunchIntentForPackage(packageName)
                ?.resolveActivityInfo(packageManager, 0)
                ?.let { buildAppMap(it, true) }
    }

    /**
     * Every app worth offering as a button mapping target.
     *
     * [getApplications] only returns what resolves a launcher intent, which
     * leaves out disabled apps — and the apps a remote has a dedicated button
     * for are exactly the ones people disable. Ask the package manager for the
     * disabled components too, then keep anything launchable plus anything
     * disabled.
     */
    @Suppress("DEPRECATION")
    private fun getMappableApplications(): List<Map<String, Serializable?>> {
        // MATCH_DISABLED_COMPONENTS alone misses the preloads that sit in the
        // DISABLED_UNTIL_USED state, which is how most TV firmware ships the
        // streaming apps people then turn off. Same values under both names;
        // the newer ones only exist from API 24.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PackageManager.MATCH_DISABLED_COMPONENTS or
                PackageManager.MATCH_DISABLED_UNTIL_USED_COMPONENTS
        } else {
            PackageManager.GET_DISABLED_COMPONENTS
        }
        val self = getPackageName()
        val byPackage = LinkedHashMap<String, Map<String, Serializable?>>()

        // Launchable apps first, from the same cheap query the launcher already
        // uses. This part must not depend on the bulk call below, which returns
        // every package on the device and can blow the binder transaction limit
        // on a TV with a large system image.
        for (activityInfo in queryIntentActivities(false) + queryIntentActivities(true)) {
            if (activityInfo.packageName == self) continue
            byPackage.getOrPut(activityInfo.packageName) {
                mapOf(
                    "name" to activityInfo.loadLabel(packageManager).toString(),
                    "packageName" to activityInfo.packageName,
                    "enabled" to true,
                )
            }
        }

        // Then the disabled ones, which resolve no launcher intent and so are
        // invisible above. Best effort: if this fails the list is still usable.
        try {
            for (info in packageManager.getInstalledApplications(flags)) {
                if (info.packageName == self || byPackage.containsKey(info.packageName)) continue
                if (!isDisabled(info)) continue
                byPackage[info.packageName] = mapOf(
                    "name" to runCatching { info.loadLabel(packageManager).toString() }
                        .getOrDefault(info.packageName),
                    "packageName" to info.packageName,
                    "enabled" to false,
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("FLauncher", "Could not list disabled applications", e)
        }

        return byPackage.values.sortedBy { (it["name"] as String).lowercase() }
    }

    /**
     * Whether the user has switched this app off.
     *
     * [ApplicationInfo.enabled] misses `DISABLED_UNTIL_USED`, the state most TV
     * preloads sit in, so ask for the enabled setting as well.
     */
    private fun isDisabled(info: ApplicationInfo): Boolean {
        if (!info.enabled) return true
        val setting = try {
            packageManager.getApplicationEnabledSetting(info.packageName)
        } catch (e: IllegalArgumentException) {
            return false
        }
        return setting == PackageManager.COMPONENT_ENABLED_STATE_DISABLED ||
            setting == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER ||
            setting == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED
    }

    private fun applicationExists(packageName: String) = try {
        packageManager.getApplicationInfo(packageName, 0)
        val intent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
            ?: packageManager.getLaunchIntentForPackage(packageName)
        intent != null
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun queryIntentActivities(sideloaded: Boolean) = packageManager
            .queryIntentActivities(Intent(ACTION_MAIN, null)
                    .addCategory(if (sideloaded) CATEGORY_LAUNCHER else CATEGORY_LEANBACK_LAUNCHER), 0)
            .map(ResolveInfo::activityInfo)

    private fun buildAppMap(activityInfo: ActivityInfo, sideloaded: Boolean): Map<String, Serializable?> {
        val packageInfo = packageManager.getPackageInfo(activityInfo.packageName, 0)
        val isSystemApp = (packageInfo.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
        return mapOf(
            "name" to activityInfo.loadLabel(packageManager).toString(),
            "packageName" to activityInfo.packageName,
            "banner" to activityInfo.loadBanner(packageManager)?.let(::drawableToByteArray),
            "icon" to activityInfo.loadIcon(packageManager)?.let(::drawableToByteArray),
            "version" to packageInfo.versionName,
            "sideloaded" to sideloaded,
            "isSystemApp" to isSystemApp,
        )
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

    private fun getTvInputInfo(inputId: String): TvInputInfo? = try {
        val tvInputManager = getSystemService(TV_INPUT_SERVICE) as TvInputManager
        tvInputManager.getTvInputInfo(inputId)
    } catch (e: Exception) {
        // Log error maybe?
        null
    }

    private fun getHdmiInputs(): List<Map<String, Serializable?>> {
        return try {
            val tvInputManager = getSystemService(TV_INPUT_SERVICE) as TvInputManager
            tvInputManager.tvInputList
                .filter { it.type == TvInputInfo.TYPE_HDMI }
                .map { buildTvInputMap(it) }
        } catch (e: Exception) {
            // Log error maybe?
            emptyList()
        }
    }

    private fun buildTvInputMap(inputInfo: TvInputInfo): Map<String, Serializable?> = mapOf(
        "id" to inputInfo.id,
        "name" to inputInfo.loadLabel(context).toString(),
        "type" to inputInfo.type,
        "icon" to inputInfo.loadIcon(context)?.let(::drawableToByteArray), // Optional icon
        // Add other relevant fields if needed, e.g., inputInfo.loadCustomLabel(context)?.toString()
    )

    private fun launchTvInput(inputId: String?): Boolean {
        if (inputId == null) return false
        
        android.util.Log.d("FLauncher", "Attempting to launch TV input: $inputId")
        
        return try {
            val tvInputManager = getSystemService(TV_INPUT_SERVICE) as TvInputManager
            val tvInputInfo = tvInputManager.getTvInputInfo(inputId)
            
            if (tvInputInfo == null) {
                android.util.Log.e("FLauncher", "Failed to get TV input info for ID: $inputId")
                return false
            }
            
            // Extract HDMI port information from input name or ID
            val inputName = tvInputInfo.loadLabel(context).toString()
            val portNumber = when {
                inputName.contains("1") -> 1
                inputName.contains("2") -> 2
                inputName.contains("3") -> 3
                inputName.contains("4") -> 4
                else -> inputId.split("/").lastOrNull()?.toIntOrNull() ?: 1
            }
            
            // For MediaTek TVs, we need both approaches - standard Android TV API and MediaTek specific methods
            
            // 1. Standard Android TV approach - create URI for the input
            try {
                // Create a passthrough channel URI for this input
                val channelUri = android.media.tv.TvContract.buildChannelUriForPassthroughInput(inputId)
                
                // Create a standard VIEW intent with the channel URI
                val intent = Intent(Intent.ACTION_VIEW, channelUri).apply {
                    // These flags are important for proper input switching
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    
                    // If we know the specific component for MediaTek
                    if (isMediaTekTv()) {
                        component = ComponentName(
                            "com.mediatek.wwtv.tvcenter",
                            "com.mediatek.wwtv.tvcenter.nav.TurnkeyUiMainActivity"
                        )
                        // Important extras for MediaTek
                        putExtra("from_launcher", true)
                        putExtra("source_flag", 4) // HDMI source type
                        
                        // MediaTek source ID mapping (based on testing)
                        val mtSourceValue = when (portNumber) {
                            1 -> 23  // HDMI1
                            2 -> 25  // HDMI2 
                            3 -> 24  // HDMI3
                            4 -> 26  // HDMI4 (assumed)
                            else -> 23  // Default to HDMI1
                        }
                        putExtra("source_input_id", portNumber)
                        putExtra("mtk_input_source", mtSourceValue)
                    }
                }
                
                android.util.Log.d("FLauncher", "Starting TV input with ACTION_VIEW intent")
                startActivity(intent)
                return true
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "Standard TV input approach failed: ${e.message}")
                // Fall through to MediaTek specific approach
            }
            
            // 2. MediaTek-specific approach as fallback
            try {
                // MediaTek source ID mapping (based on testing)
                val mtSourceValue = when (portNumber) {
                    1 -> 23  // HDMI1
                    2 -> 25  // HDMI2 
                    3 -> 24  // HDMI3
                    4 -> 26  // HDMI4 (assumed)
                    else -> 23  // Default to HDMI1
                }
                
                // Try to directly use the MediaTek TV service through reflection
                try {
                    val tvServiceClass = Class.forName("com.mediatek.twoworlds.tv.MtkTvConfig")
                    val getInstance = tvServiceClass.getMethod("getInstance")
                    val tvConfig = getInstance.invoke(null)
                    
                    val cfgClass = tvConfig.javaClass
                    val setInputSourceMethod = cfgClass.getMethod("setInputSource", Int::class.java)
                    
                    android.util.Log.d("FLauncher", "Setting MediaTek input source directly to $mtSourceValue")
                    setInputSourceMethod.invoke(tvConfig, mtSourceValue)
                    return true
                } catch (e: Exception) {
                    android.util.Log.w("FLauncher", "MediaTek direct API call failed: ${e.message}")
                    // Fall through to component intent
                }
                
                // Launch the MediaTek TurnkeyUiMainActivity directly
                val activityIntent = Intent().apply {
                    component = ComponentName(
                        "com.mediatek.wwtv.tvcenter", 
                        "com.mediatek.wwtv.tvcenter.nav.TurnkeyUiMainActivity"
                    )
                    // Essential extras for MediaTek TVs
                    putExtra("from_launcher", true)
                    putExtra("source_flag", 4)
                    putExtra("source_input_id", portNumber)
                    putExtra("mtk_input_source", mtSourceValue)
                    
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                
                // First send a broadcast to prepare the system
                val prepIntent = Intent("tv.mediatek.intent.action.TV_INPUT").apply {
                    putExtra("from_launcher", true)
                    putExtra("source_flag", 4)
                    putExtra("source_input_id", portNumber)
                    putExtra("mtk_input_source", mtSourceValue)
                }
                sendBroadcast(prepIntent)
                
                android.util.Log.d("FLauncher", "Starting MediaTek TV input directly")
                startActivity(activityIntent)
                return true
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "All TV input launch methods failed: ${e.message}")
                e.printStackTrace()
                return false
            }
        } catch (e: Exception) {
            android.util.Log.e("FLauncher", "Error in launchTvInput: ${e.message}")
            e.printStackTrace()
            return false
        }
    }
    
    /**
     * Check if this is likely a MediaTek TV
     */
    private fun isMediaTekTv(): Boolean {
        return try {
            // Try to access a MediaTek specific class
            Class.forName("com.mediatek.twoworlds.tv.MtkTvConfig")
            true
        } catch (e: ClassNotFoundException) {
            // Look for MediaTek packages
            try {
                packageManager.getPackageInfo("com.mediatek.wwtv.tvcenter", 0)
                true
            } catch (e: Exception) {
                false
            }
        }
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

    private fun drawableToByteArray(drawable: Drawable): ByteArray? {
        if (drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) {
            return null
        }

        fun drawableToBitmap(drawable: Drawable): Bitmap {
            val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

        val bitmap = drawableToBitmap(drawable)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    private fun canRequestPackageInstalls(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return packageManager.canRequestPackageInstalls()
        }
        return true
    }

    private fun requestPackageInstallsPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "Error opening unknown sources settings: ${e.message}")
                return false
            }
        }
        return true
    }

    private fun installApk(filePath: String): String {
        val file = File(filePath)
        if (!file.exists()) return "file_missing"

        if (isDeviceOwnerApp()) {
            try {
                val packageInstaller = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                val sessionId = packageInstaller.createSession(params)
                val session = packageInstaller.openSession(sessionId)

                FileInputStream(file).use { input ->
                    session.openWrite("base.apk", 0, -1).use { output ->
                        val buffer = ByteArray(1024 * 64)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                        }
                        output.flush()
                        session.fsync(output)
                    }
                }

                val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
                val pendingIntent = PendingIntent.getActivity(this, sessionId, Intent(this, MainActivity::class.java), flags)
                session.commit(pendingIntent.intentSender)
                session.close()
                return "silent_started"
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "Silent install attempt failed: ${e.message}")
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canInstall = try {
                packageManager.canRequestPackageInstalls()
            } catch (e: SecurityException) {
                android.util.Log.e("FLauncher", "Missing REQUEST_INSTALL_PACKAGES in manifest: ${e.message}")
                return "missing_manifest_permission"
            }

            if (!canInstall) {
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    return "needs_permission"
                } catch (e: Exception) {
                    android.util.Log.e("FLauncher", "Error opening unknown sources settings: ${e.message}")
                    return "needs_permission"
                }
            }
        }

        return try {
            val uri = FileProvider.getUriForFile(
                this,
                applicationContext.packageName + ".fileprovider",
                file
            )

            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE)
            intent.data = uri
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            startActivity(intent)
            "started"
        } catch (e: Exception) {
            android.util.Log.e("FLauncher", "Error installing APK: ${e.message}")
            e.printStackTrace()
            "error"
        }
    }

    private fun isDeviceOwnerApp(): Boolean {
        return try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.isDeviceOwnerApp(packageName)
        } catch (_: Exception) {
            false
        }
    }
}
