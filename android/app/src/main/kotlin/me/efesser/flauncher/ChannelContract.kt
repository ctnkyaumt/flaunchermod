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

/** Channel names and event keys shared with lib/flauncher_channel.dart. */
internal object ChannelContract {
    const val METHOD_CHANNEL = "me.efesser.flauncher/method"
    const val EVENT_CHANNEL = "me.efesser.flauncher/event"
    const val HDMI_EVENT_CHANNEL = "me.efesser.flauncher/hdmi_event"
    const val KEY_CAPTURE_EVENT_CHANNEL = "me.efesser.flauncher/key_capture_event"
    const val NETWORK_EVENT_CHANNEL = "me.efesser.flauncher/network_event"

    /** Every package and TV input event carries its kind under this key. */
    const val KEY_ACTION = "action"

    // Package events (EVENT_CHANNEL).
    const val ACTION_PACKAGE_REMOVED = "PACKAGE_REMOVED"
    const val ACTION_PACKAGE_ADDED = "PACKAGE_ADDED"
    const val ACTION_PACKAGE_CHANGED = "PACKAGE_CHANGED"
    const val ACTION_PACKAGES_AVAILABLE = "PACKAGES_AVAILABLE"
    const val KEY_PACKAGE_NAME = "packageName"
    const val KEY_ACTIVITY_INFO = "activityInfo"
    const val KEY_ACTIVITIES_INFO = "activitiesInfo"

    // TV input events (HDMI_EVENT_CHANNEL).
    const val ACTION_INPUT_ADDED = "INPUT_ADDED"
    const val ACTION_INPUT_REMOVED = "INPUT_REMOVED"
    const val ACTION_INPUT_UPDATED = "INPUT_UPDATED"
    const val ACTION_INPUT_STATE_CHANGED = "INPUT_STATE_CHANGED"
    const val KEY_INPUT_INFO = "inputInfo"
    const val KEY_INPUT_ID = "inputId"
    const val KEY_STATE = "state"

    // Key capture events (KEY_CAPTURE_EVENT_CHANNEL).
    const val KEY_CAPTURE_CANCELLED = "captureCancelled"
    const val KEY_KEY_CODE = "keyCode"
    const val KEY_SCAN_CODE = "scanCode"
    const val KEY_KEY_LABEL = "keyLabel"
    const val KEY_KEY_ACTION = "keyAction"
    const val KEY_DEVICE = "device"
    const val KEY_RAW_CODE = "rawCode"
    const val KEY_RAW_SCAN_CODE = "rawScanCode"
}
