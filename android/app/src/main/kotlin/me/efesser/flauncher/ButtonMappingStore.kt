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

import android.content.Context
import org.json.JSONObject

/**
 * Reads the button mapping table written by the Flutter side.
 *
 * The table is persisted as a single JSON string inside the same
 * `FlutterSharedPreferences` file that the `shared_preferences` plugin uses, so
 * the accessibility service can read it without the launcher process running.
 * A single JSON blob is used rather than a `StringList` because the plugin
 * encodes lists with its own prefix scheme that is awkward to parse natively.
 */
object ButtonMappingStore {
    const val PREFERENCES_NAME = "FlutterSharedPreferences"
    const val MAPPINGS_KEY = "flutter.button_mappings"

    /** How a button press was classified. */
    enum class Trigger { SINGLE, DOUBLE, LONG }

    /** Action carried out when a mapped button fires. */
    sealed class Action {
        /** Launch an installed package by name. */
        data class LaunchApp(val packageName: String) : Action()

        /** Bring FLauncher itself to the foreground. */
        object OpenFlauncher : Action()

        /** Open the system settings screen. */
        object OpenSettings : Action()

        /** Swallow the button so nothing happens at all. */
        object Block : Action()

        companion object {
            fun fromJson(json: JSONObject?): Action? {
                if (json == null) return null
                return when (json.optString("type")) {
                    "launchApp" -> json.optString("packageName")
                        .takeIf { it.isNotEmpty() }
                        ?.let { LaunchApp(it) }
                    "openFlauncher" -> OpenFlauncher
                    "openSettings" -> OpenSettings
                    "block" -> Block
                    else -> null
                }
            }
        }
    }

    /**
     * One physical remote button and what it should do.
     *
     * Buttons are matched on scan code first when the event carries one. Many TV
     * remote extras (Netflix, YouTube, Prime, ...) all report `KEYCODE_UNKNOWN`
     * so keying on the key code alone would collapse them onto each other, but
     * their scan codes are distinct.
     */
    data class Binding(
        val keyCode: Int,
        val scanCode: Int?,
        val single: Action?,
        val double: Action?,
        val long: Action?,
    ) {
        fun actionFor(trigger: Trigger): Action? = when (trigger) {
            Trigger.SINGLE -> single
            Trigger.DOUBLE -> double
            Trigger.LONG -> long
        }

        val hasDouble: Boolean get() = double != null
        val hasLong: Boolean get() = long != null
        val hasAny: Boolean get() = single != null || double != null || long != null

        companion object {
            fun fromJson(json: JSONObject): Binding? {
                if (!json.has("keyCode")) return null
                val keyCode = json.optInt("keyCode", -1)
                if (keyCode < 0) return null
                val scanCode = if (json.has("scanCode") && !json.isNull("scanCode")) {
                    json.optInt("scanCode").takeIf { it != 0 }
                } else {
                    null
                }
                val binding = Binding(
                    keyCode = keyCode,
                    scanCode = scanCode,
                    single = Action.fromJson(json.optJSONObject("single")),
                    double = Action.fromJson(json.optJSONObject("double")),
                    long = Action.fromJson(json.optJSONObject("long")),
                )
                return if (binding.hasAny) binding else null
            }
        }
    }

    data class Mappings(
        val bindings: List<Binding> = emptyList(),
        val appRedirects: Map<String, Action> = emptyMap(),
    ) {
        /**
         * Finds the binding for an incoming event. A non-zero scan code is the
         * more specific signal, so it wins; key code is the fallback for the
         * ordinary buttons that report one properly.
         */
        fun resolve(keyCode: Int, scanCode: Int): Binding? {
            if (scanCode != 0) {
                bindings.firstOrNull { it.scanCode != null && it.scanCode == scanCode }
                    ?.let { return it }
            }
            return bindings.firstOrNull { it.scanCode == null && it.keyCode == keyCode }
        }
    }

    fun load(context: Context): Mappings {
        val raw = context
            .getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getString(MAPPINGS_KEY, null)
            ?: return Mappings()
        return parse(raw)
    }

    fun parse(raw: String): Mappings {
        return try {
            val root = JSONObject(raw)

            val bindings = mutableListOf<Binding>()
            val keyArray = root.optJSONArray("keyMappings")
            if (keyArray != null) {
                for (i in 0 until keyArray.length()) {
                    val entry = keyArray.optJSONObject(i) ?: continue
                    Binding.fromJson(entry)?.let { bindings.add(it) }
                }
            }

            val appRedirects = mutableMapOf<String, Action>()
            val redirectArray = root.optJSONArray("appRedirects")
            if (redirectArray != null) {
                for (i in 0 until redirectArray.length()) {
                    val entry = redirectArray.optJSONObject(i) ?: continue
                    val source = entry.optString("sourcePackage").takeIf { it.isNotEmpty() } ?: continue
                    val action = Action.fromJson(entry.optJSONObject("action")) ?: continue
                    appRedirects[source] = action
                }
            }

            Mappings(bindings, appRedirects)
        } catch (e: Exception) {
            Mappings()
        }
    }
}
