/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import android.content.Intent
import android.content.Intent.*
import android.content.pm.*
import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
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
import java.io.Serializable

private const val METHOD_CHANNEL = "me.efesser.flauncher/method"
private const val EVENT_CHANNEL = "me.efesser.flauncher/event"
private const val HDMI_EVENT_CHANNEL = "me.efesser.flauncher/hdmi_event"

class MainActivity : FlutterActivity() {
    val launcherAppsCallbacks = ArrayList<LauncherApps.Callback>()
    private var tvInputCallback: TvInputCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())

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
                    "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                    "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                    "isDefaultLauncher" -> result.success(isDefaultLauncher())
                    "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability())
                    "startAmbientMode" -> result.success(startAmbientMode())
                    "getHdmiInputs" -> result.success(getHdmiInputs())
                    "launchTvInput" -> result.success(launchTvInput(call.argument<String>("inputId")))
                    "shutdownDevice" -> result.success(shutdownDevice())
                    "installApk" -> result.success(installApk(call.arguments as String))
                    "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
                    "requestPackageInstallsPermission" -> result.success(requestPackageInstallsPermission())
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
    }

    override fun onDestroy() {
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

    private fun applicationExists(packageName: String) = try {
        val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PackageManager.MATCH_UNINSTALLED_PACKAGES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_UNINSTALLED_PACKAGES
        }
        packageManager.getApplicationInfo(packageName, flag)
        true
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

    /**
     * Shutdown the device
     * This implementation is based on Android's ShutdownThread implementation
     * to properly shut down the device instead of restarting it
     */
    private fun shutdownDevice(): Boolean {
        android.util.Log.d("FLauncher", "Attempting to shutdown device using system methods")
        
        try {
            // Set the shutdown property that Android system checks
            // This is equivalent to what ShutdownThread does
            try {
                android.util.Log.i("FLauncher", "Setting shutdown property")
                val shutdownActionProperty = "sys.shutdown.requested"
                // Use reflection to access SystemProperties since it's a hidden API
                val systemPropertiesClass = Class.forName("android.os.SystemProperties")
                val setMethod = systemPropertiesClass.getMethod("set", String::class.java, String::class.java)
                setMethod.invoke(null, shutdownActionProperty, "0") // 0 means shutdown (not reboot)
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "Failed to set shutdown property: ${e.message}")
            }
            
            // 1. Try to use the PowerManagerService directly through reflection
            try {
                android.util.Log.i("FLauncher", "Attempting PowerManagerService.lowLevelShutdown")
                val powerManagerServiceClass = Class.forName("com.android.server.power.PowerManagerService")
                val lowLevelShutdownMethod = powerManagerServiceClass.getDeclaredMethod("lowLevelShutdown", String::class.java)
                lowLevelShutdownMethod.isAccessible = true
                lowLevelShutdownMethod.invoke(null, null)
                return true
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "PowerManagerService.lowLevelShutdown failed: ${e.message}")
            }
            
            // 2. Try to use ShutdownThread directly
            try {
                android.util.Log.i("FLauncher", "Attempting ShutdownThread.shutdown")
                val shutdownThreadClass = Class.forName("com.android.server.power.ShutdownThread")
                val contextClass = Class.forName("android.content.Context")
                val shutdownMethod = shutdownThreadClass.getDeclaredMethod("shutdown", contextClass, String::class.java, Boolean::class.java)
                shutdownMethod.isAccessible = true
                shutdownMethod.invoke(null, this, "userrequested", false)
                return true
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "ShutdownThread.shutdown failed: ${e.message}")
            }
            
            // 3. MediaTek specific approaches for MediaTek TVs
            if (isMediaTekTv()) {
                android.util.Log.i("FLauncher", "Detected MediaTek TV, trying MediaTek specific methods")
                
                // Try to use the MediaTek power service
                try {
                    val tvServiceClass = Class.forName("com.mediatek.twoworlds.tv.MtkTvPower")
                    val getInstance = tvServiceClass.getMethod("getInstance")
                    val tvPower = getInstance.invoke(null)
                    
                    // Try the direct shutdown method
                    try {
                        val method = tvPower.javaClass.getMethod("shutdown")
                        method.invoke(tvPower)
                        android.util.Log.i("FLauncher", "MtkTvPower.shutdown successful")
                        return true
                    } catch (e: Exception) {
                        android.util.Log.e("FLauncher", "MtkTvPower.shutdown failed: ${e.message}")
                    }
                    
                    // Try setPowerOff method
                    try {
                        val method = tvPower.javaClass.getMethod("setPowerOff", Boolean::class.java)
                        method.invoke(tvPower, true)
                        android.util.Log.i("FLauncher", "MtkTvPower.setPowerOff successful")
                        return true
                    } catch (e: Exception) {
                        android.util.Log.e("FLauncher", "MtkTvPower.setPowerOff failed: ${e.message}")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("FLauncher", "MtkTvPower access failed: ${e.message}")
                }
                
                // Try MediaTek specific broadcast intents
                try {
                    // This is the most common MediaTek power intent
                    val intent = Intent("com.mediatek.wwtv.tvcenter.power")
                    intent.putExtra("powerState", "shutdown")
                    sendBroadcast(intent)
                    android.util.Log.i("FLauncher", "MediaTek power broadcast sent")
                    return true
                } catch (e: Exception) {
                    android.util.Log.e("FLauncher", "MediaTek power broadcast failed: ${e.message}")
                }
            }
            
            // 4. Try standard Android shutdown intent
            try {
                android.util.Log.i("FLauncher", "Attempting standard shutdown intent")
                val intent = Intent("android.intent.action.ACTION_REQUEST_SHUTDOWN")
                intent.putExtra("android.intent.extra.KEY_CONFIRM", false)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                return true
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "Standard shutdown intent failed: ${e.message}")
            }
            
            // 5. Try using IPowerManager interface
            try {
                android.util.Log.i("FLauncher", "Attempting IPowerManager shutdown")
                val powerManager = getSystemService(POWER_SERVICE) as android.os.PowerManager
                val powerManagerClass = powerManager.javaClass
                
                // Get the IPowerManager interface
                val getServiceMethod = powerManagerClass.getDeclaredMethod("getService")
                getServiceMethod.isAccessible = true
                val powerManagerService = getServiceMethod.invoke(null)
                
                if (powerManagerService != null) {
                    val shutdownMethod = powerManagerService.javaClass.getMethod("shutdown", Boolean::class.java, String::class.java, Boolean::class.java)
                    shutdownMethod.invoke(powerManagerService, false, null, false)
                    android.util.Log.i("FLauncher", "IPowerManager.shutdown successful")
                    return true
                }
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "IPowerManager shutdown failed: ${e.message}")
            }
            
            // 6. Last resort - system commands
            val commands = listOf(
                "setprop sys.powerctl shutdown", // This is what PowerManagerService.lowLevelShutdown uses
                "reboot -p",                   // Standard Linux command for poweroff
                "svc power shutdown"           // Android service control command
            )
            
            for (command in commands) {
                try {
                    android.util.Log.i("FLauncher", "Executing command: $command")
                    // Try with and without su
                    try {
                        Runtime.getRuntime().exec(command)
                    } catch (e: Exception) {
                        Runtime.getRuntime().exec("su -c '$command'")
                    }
                    return true
                } catch (e: Exception) {
                    android.util.Log.e("FLauncher", "Command failed: $command - ${e.message}")
                }
            }
            
            android.util.Log.e("FLauncher", "All shutdown methods failed")
            return false
        } catch (e: Exception) {
            android.util.Log.e("FLauncher", "Error in shutdownDevice: ${e.message}")
            e.printStackTrace()
            return false
        }
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
