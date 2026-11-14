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

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.tv.TvInputInfo
import android.media.tv.TvInputManager
import java.io.Serializable

/**
 * The TV's inputs (HDMI, tuner, AV...): listing them for the Inputs page and
 * switching to one. Switching starts an activity, so call it on the UI thread.
 */
internal class TvInputs(private val context: Context) {
    private val tvInputManager: TvInputManager
        get() = context.getSystemService(Context.TV_INPUT_SERVICE) as TvInputManager

    fun getTvInputInfo(inputId: String): TvInputInfo? = try {
        tvInputManager.getTvInputInfo(inputId)
    } catch (e: Exception) {
        // Log error maybe?
        null
    }

    /** Every input the system reports, hidden ones included, as plain data. */
    private fun allSpecs(): List<TvInputSpec> = tvInputManager.tvInputList.map { inputInfo ->
        TvInputSpec(
            id = inputInfo.id,
            type = inputInfo.type,
            customLabel = inputInfo.loadCustomLabel(context)?.toString(),
            label = inputInfo.loadLabel(context)?.toString(),
            hidden = inputInfo.isHidden(context),
        )
    }

    private fun classify(): TvInputGroups = TvInputCatalog.classify(allSpecs())

    fun getHdmiInputs(): List<Map<String, Serializable?>> = try {
        classify().hdmi.map(::entryMap)
    } catch (e: Exception) {
        emptyList()
    }

    fun getTvInputs(): List<Map<String, Serializable?>> = try {
        val groups = classify()
        (groups.hdmi + groups.other).map(::entryMap)
    } catch (e: Exception) {
        emptyList()
    }

    /** The entry the Inputs page would show for [inputId], or null when it is hidden or deduplicated away. */
    fun findShownTvInput(inputId: String): TvInputEntry? = try {
        val groups = classify()
        (groups.hdmi + groups.other).firstOrNull { it.id == inputId }
    } catch (e: Exception) {
        null
    }

    fun entryMap(entry: TvInputEntry): Map<String, Serializable?> = mapOf(
        "id" to entry.id,
        "name" to entry.name,
        "type" to entry.type,
        "group" to entry.group,
    )

    /** The HDMI port of [inputId]; see [TvInputCatalog.hdmiPort]. */
    private fun hdmiPortOf(inputId: String, info: TvInputInfo): Int {
        val all = try {
            allSpecs()
        } catch (e: Exception) {
            emptyList()
        }
        val self = all.firstOrNull { it.id == inputId } ?: TvInputSpec(
            id = inputId,
            type = TvInputCatalog.TYPE_HDMI,
            customLabel = null,
            label = info.loadLabel(context)?.toString(),
            hidden = false,
        )
        return TvInputCatalog.hdmiPort(self, all)
    }

    fun launchTvInput(inputId: String?): Boolean {
        if (inputId == null) return false

        android.util.Log.d("FLauncher", "Attempting to launch TV input: $inputId")

        return try {
            val tvInputInfo = tvInputManager.getTvInputInfo(inputId)

            if (tvInputInfo == null) {
                android.util.Log.e("FLauncher", "Failed to get TV input info for ID: $inputId")
                return false
            }

            if (tvInputInfo.type != TvInputInfo.TYPE_HDMI) return launchNonHdmiTvInput(inputId)

            // The public API does not expose the HDMI port: take it from a
            // strict "HDMI <n>" label, else from the input's position.
            val portNumber = hdmiPortOf(inputId, tvInputInfo)
            // MediaTek source ID mapping (based on testing)
            val mtSourceValue = TvInputCatalog.mediaTekSource(portNumber)

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
                        putExtra("source_input_id", portNumber)
                        putExtra("mtk_input_source", mtSourceValue)
                    }
                }

                android.util.Log.d("FLauncher", "Starting TV input with ACTION_VIEW intent")
                context.startActivity(intent)
                return true
            } catch (e: Exception) {
                android.util.Log.w("FLauncher", "Standard TV input approach failed: ${e.message}")
                // Fall through to MediaTek specific approach
            }

            // 2. MediaTek-specific approach as fallback
            try {
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
                context.sendBroadcast(prepIntent)

                android.util.Log.d("FLauncher", "Starting MediaTek TV input directly")
                context.startActivity(activityIntent)
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
     * Switches to a tuner/AV/component/VGA input. Carries none of the HDMI port extras:
     * the passthrough URI alone selects the input.
     */
    private fun launchNonHdmiTvInput(inputId: String): Boolean = try {
        val intent = Intent(Intent.ACTION_VIEW, android.media.tv.TvContract.buildChannelUriForPassthroughInput(inputId)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (isMediaTekTv()) {
                component = ComponentName(
                    "com.mediatek.wwtv.tvcenter",
                    "com.mediatek.wwtv.tvcenter.nav.TurnkeyUiMainActivity"
                )
            }
        }
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        android.util.Log.e("FLauncher", "Failed to launch non-HDMI TV input $inputId: ${e.message}")
        false
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
                context.packageManager.getPackageInfo("com.mediatek.wwtv.tvcenter", 0)
                true
            } catch (e: Exception) {
                false
            }
        }
    }
}
