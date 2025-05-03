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
                "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                "isDefaultLauncher" -> result.success(isDefaultLauncher())
                "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability())
                "startAmbientMode" -> result.success(startAmbientMode())
                "getHdmiInputs" -> result.success(getHdmiInputs())
                "launchTvInput" -> result.success(launchTvInput(call.argument<String>("inputId")))
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
            
            // MediaTek HDMI port identification
            // Usually the port number should be derived from the HDMI input name
            // e.g., "HDMI1" -> port 1, "HDMI2" -> port 2, etc.
            val inputName = tvInputInfo.loadLabel(context).toString()
            val portNumber = when {
                inputName.contains("1") -> 1
                inputName.contains("2") -> 2
                inputName.contains("3") -> 3
                inputName.contains("4") -> 4
                // Fallback to parsing from ID as before
                else -> inputId.split("/").lastOrNull()?.toIntOrNull() ?: 1
            }
            
            // MediaTek internal source values:
            // 23 = HDMI1, 24 = HDMI2, 25 = HDMI3, 26 = HDMI4 (based on log analysis)
            val mtSourceValue = 22 + portNumber
            
            // MediaTek specific TV input service method
            try {
                // First approach: Use MediaTek's TV service to directly set input source
                val tvServiceClass = Class.forName("com.mediatek.twoworlds.tv.MtkTvConfig")
                val getInstance = tvServiceClass.getMethod("getInstance")
                val tvConfig = getInstance.invoke(null)
                
                // Set input source directly through MediaTek API
                val cfgClass = tvConfig.javaClass
                val setInputSourceMethod = cfgClass.getMethod("setInputSource", Int::class.java)
                
                android.util.Log.d("FLauncher", "Setting MediaTek input source directly to $mtSourceValue for port $portNumber")
                setInputSourceMethod.invoke(tvConfig, mtSourceValue)
                
                // Success - direct API call worked
                return true
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "MediaTek direct API call failed: ${e.message}")
                // Continue with other approaches
            }
            
            // Second approach: Use Intent with feature operation action
            try {
                val featureIntent = Intent("com.mediatek.intent.action.START_TV_FEATURE_OPERATION")
                featureIntent.putExtra("feature_operation_type", "tv_input")
                featureIntent.putExtra("input_source_type", 4) // HDMI type
                featureIntent.putExtra("input_source_port", portNumber)
                featureIntent.putExtra("mtk_input_source", mtSourceValue)
                featureIntent.putExtra("from_launcher", true)
                
                android.util.Log.d("FLauncher", "Trying MediaTek feature operation intent for source $mtSourceValue")
                sendBroadcast(featureIntent)
                featureIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(featureIntent)
                return true
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "MediaTek feature operation intent failed: ${e.message}")
            }
            
            // Third approach: Try TurnkeyUiMainActivity with extended parameters
            try {
                val activityIntent = Intent().apply {
                    component = ComponentName(
                        "com.mediatek.wwtv.tvcenter", 
                        "com.mediatek.wwtv.tvcenter.nav.TurnkeyUiMainActivity"
                    )
                    // Critical MediaTek TV extras
                    putExtra("from_launcher", true)
                    putExtra("source_flag", 4)
                    putExtra("source_input_id", portNumber)
                    putExtra("force_input_selection", true)
                    putExtra("ignore_active_detection", true)
                    putExtra("mtk_input_source", mtSourceValue) // Specific MediaTek source ID
                    putExtra("tv_input_port_id", mtSourceValue)
                    putExtra("set_input_directly", true)
                    
                    // Add flags
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                
                // First send a broadcast to prepare the system
                val prepIntent = Intent("tv.mediatek.intent.action.TV_INPUT")
                prepIntent.putExtra("from_launcher", true)
                prepIntent.putExtra("source_flag", 4)
                prepIntent.putExtra("source_input_id", portNumber)
                prepIntent.putExtra("mtk_input_source", mtSourceValue)
                sendBroadcast(prepIntent)
                
                // Short delay to allow broadcast to be processed
                Thread.sleep(100)
                
                // Then start activity
                android.util.Log.d("FLauncher", "Starting TurnkeyUiMainActivity with mtk_input_source=$mtSourceValue")
                startActivity(activityIntent)
                return true
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "All TV input launch methods failed")
                e.printStackTrace()
                return false
            }
        } catch (e: Exception) {
            android.util.Log.e("FLauncher", "Error in launchTvInput: ${e.message}")
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
