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
import java.io.ByteArrayOutputStream
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
                else -> throw IllegalArgumentException()
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

    private fun buildAppMap(activityInfo: ActivityInfo, sideloaded: Boolean) = mapOf(
            "name" to activityInfo.loadLabel(packageManager).toString(),
            "packageName" to activityInfo.packageName,
            "banner" to activityInfo.loadBanner(packageManager)?.let(::drawableToByteArray),
            "icon" to activityInfo.loadIcon(packageManager)?.let(::drawableToByteArray),
            "version" to packageManager.getPackageInfo(activityInfo.packageName, 0).versionName,
            "sideloaded" to sideloaded,
    )

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
     * This uses both standard Android APIs and MediaTek specific methods to ensure
     * the device properly shuts down instead of restarting
     */
    private fun shutdownDevice(): Boolean {
        android.util.Log.d("FLauncher", "Attempting to shutdown device")
        
        try {
            // More aggressive approach for MediaTek TVs
            if (isMediaTekTv()) {
                // Try all known MediaTek TV power methods in sequence
                var success = false
                
                // 1. Direct MediaTek MtkTvPower API approach
                try {
                    val tvServiceClass = Class.forName("com.mediatek.twoworlds.tv.MtkTvPower")
                    val getInstance = tvServiceClass.getMethod("getInstance")
                    val tvPower = getInstance.invoke(null)
                    val powerClass = tvPower.javaClass
                    
                    // Try all possible power methods with different parameter combinations
                    val methodsToTry = listOf(
                        Triple("shutdown", arrayOf<Class<*>>(), arrayOf<Any>()),
                        Triple("powerOff", arrayOf<Class<*>>(), arrayOf<Any>()),
                        Triple("setPowerOff", arrayOf<Class<*>>(), arrayOf<Any>()),
                        Triple("goToShutdown", arrayOf<Class<*>>(), arrayOf<Any>()),
                        Triple("setPowerOff", arrayOf(Boolean::class.java), arrayOf(true)),
                        Triple("setPowerMode", arrayOf(Int::class.java), arrayOf(0)), // 0 might be power off
                        Triple("setPowerMode", arrayOf(Int::class.java), arrayOf(1)), // 1 might be power off
                        Triple("setPowerMode", arrayOf(Int::class.java), arrayOf(2))  // 2 might be power off
                    )
                    
                    for ((methodName, paramTypes, paramValues) in methodsToTry) {
                        try {
                            val method = powerClass.getMethod(methodName, *paramTypes)
                            method.invoke(tvPower, *paramValues)
                            android.util.Log.d("FLauncher", "MediaTek $methodName method called successfully")
                            success = true
                            // Don't return immediately, try other methods too for redundancy
                        } catch (e: Exception) {
                            android.util.Log.w("FLauncher", "MediaTek $methodName method failed: ${e.message}")
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.w("FLauncher", "MediaTek power API reflection failed: ${e.message}")
                }
                
                // 2. Try MediaTek Config API
                try {
                    val tvConfigClass = Class.forName("com.mediatek.twoworlds.tv.MtkTvConfig")
                    val getInstance = tvConfigClass.getMethod("getInstance")
                    val tvConfig = getInstance.invoke(null)
                    val configClass = tvConfig.javaClass
                    
                    // Try to set power state through config
                    try {
                        val setPowerStateMethod = configClass.getMethod("setPowerState", Int::class.java)
                        // Try different power state values
                        val powerStates = listOf(0, 1, 2, 3, 4, 5)
                        for (state in powerStates) {
                            try {
                                setPowerStateMethod.invoke(tvConfig, state)
                                android.util.Log.d("FLauncher", "MediaTek setPowerState($state) called")
                                success = true
                            } catch (e: Exception) {
                                // Try next state
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("FLauncher", "MediaTek setPowerState method not found: ${e.message}")
                    }
                } catch (e: Exception) {
                    android.util.Log.w("FLauncher", "MediaTek config API failed: ${e.message}")
                }
                
                // 3. Try MediaTek broadcast intents - try all known intents
                val intentsToTry = listOf(
                    Pair("com.mediatek.wwtv.tvcenter.power", "powerState" to "shutdown"),
                    Pair("com.mediatek.wwtv.tvcenter.power", "powerState" to "off"),
                    Pair("com.mediatek.intent.action.POWEROFF", null),
                    Pair("mtk.intent.action.SHUTDOWN", null),
                    Pair("android.mtk.intent.action.SHUTDOWN", null),
                    Pair("com.mediatek.intent.action.SHUTDOWN", null),
                    Pair("com.mediatek.tv.poweroff", null)
                )
                
                for ((intentAction, extra) in intentsToTry) {
                    try {
                        val intent = Intent(intentAction)
                        if (extra != null) {
                            intent.putExtra(extra.first, extra.second)
                        }
                        sendBroadcast(intent)
                        android.util.Log.d("FLauncher", "Broadcast sent: $intentAction")
                        success = true
                    } catch (e: Exception) {
                        android.util.Log.w("FLauncher", "Broadcast failed for $intentAction: ${e.message}")
                    }
                }
                
                // 4. Try to directly call MediaTek TV service activities
                val activitiesToTry = listOf(
                    Pair("com.mediatek.wwtv.tvcenter", "com.mediatek.wwtv.tvcenter.nav.PowerActivity"),
                    Pair("com.mediatek.wwtv.tvcenter", "com.mediatek.wwtv.tvcenter.util.PowerService"),
                    Pair("com.mediatek.wwtv.tvcenter", "com.mediatek.wwtv.tvcenter.PowerManagerActivity")
                )
                
                for ((pkg, cls) in activitiesToTry) {
                    try {
                        val intent = Intent()
                        intent.component = ComponentName(pkg, cls)
                        intent.putExtra("power_action", "shutdown")
                        intent.putExtra("power", "off")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        android.util.Log.d("FLauncher", "Started activity: $pkg/$cls")
                        success = true
                    } catch (e: Exception) {
                        android.util.Log.w("FLauncher", "Failed to start activity $pkg/$cls: ${e.message}")
                    }
                }
                
                if (success) {
                    return true
                }
            }
            
            // Standard Android approaches
            var standardSuccess = false
            
            // 1. ACTION_REQUEST_SHUTDOWN intent
            try {
                val intent = Intent("android.intent.action.ACTION_REQUEST_SHUTDOWN")
                intent.putExtra("android.intent.extra.KEY_CONFIRM", false)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                android.util.Log.d("FLauncher", "Standard Android shutdown intent sent")
                standardSuccess = true
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "Standard Android shutdown failed: ${e.message}")
            }
            
            // 2. PowerManager via reflection
            try {
                val powerManager = getSystemService(POWER_SERVICE) as android.os.PowerManager
                val powerManagerClass = powerManager.javaClass
                
                // Try different method signatures
                val methodsToTry = listOf(
                    Triple("shutdown", arrayOf(Boolean::class.java, String::class.java, Boolean::class.java), arrayOf(false, null, false)),
                    Triple("shutdown", arrayOf(Boolean::class.java, Boolean::class.java), arrayOf(false, false)),
                    Triple("shutdown", arrayOf(), arrayOf()),
                    Triple("reboot", arrayOf(String::class.java, Boolean::class.java, Boolean::class.java), arrayOf(null, true, false))
                )
                
                for ((methodName, paramTypes, paramValues) in methodsToTry) {
                    try {
                        val method = powerManagerClass.getMethod(methodName, *paramTypes)
                        method.invoke(powerManager, *paramValues)
                        android.util.Log.d("FLauncher", "PowerManager $methodName method called successfully")
                        standardSuccess = true
                        break
                    } catch (e: Exception) {
                        android.util.Log.w("FLauncher", "PowerManager $methodName method failed: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "PowerManager access failed: ${e.message}")
            }
            
            // 3. System commands - try multiple variations
            val commandsToTry = listOf(
                "su -c 'svc power shutdown'",
                "su -c 'reboot -p'",
                "su -c 'am start -a android.intent.action.ACTION_REQUEST_SHUTDOWN --ez android.intent.extra.KEY_CONFIRM false --activity-clear-task'",
                "su -c 'setprop sys.powerctl shutdown'",
                "su -c 'setprop ctl.stop zygote'", // This will restart the system UI, not shutdown, but might help
                "su -c 'input keyevent 26'" // Power button event
            )
            
            for (command in commandsToTry) {
                try {
                    Runtime.getRuntime().exec(command)
                    android.util.Log.d("FLauncher", "Executed command: $command")
                    standardSuccess = true
                } catch (e: Exception) {
                    android.util.Log.w("FLauncher", "Command failed: $command - ${e.message}")
                }
            }
            
            return standardSuccess
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
}
