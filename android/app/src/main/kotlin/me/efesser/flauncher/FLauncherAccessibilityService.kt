/*
 * FLaunchermod
 * Copyright (C)
 * 2026 - ctnkyaumt
 * Forked from: 2021  Étienne Fesser
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

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Intercepts remote control buttons system-wide.
 *
 * An accessibility service is the only way an ordinary app can see key events
 * while another app is in the foreground. Two mechanisms are combined:
 *
 *  - [onKeyEvent] catches buttons that emit a key event. Returning `true`
 *    consumes the event so the foreground app never sees it.
 *  - [onAccessibilityEvent] catches buttons the firmware wires directly to an
 *    app launch (Netflix, YouTube, Prime Video on some devices). Those emit no
 *    key event at all, so the only hook is to notice the target package coming
 *    to the foreground and launch something else instead.
 *
 * The mapping table is read from shared preferences rather than pushed from
 * Dart, because the launcher's Flutter engine is not running while another app
 * is in the foreground — which is exactly when remapping needs to work.
 *
 * Not interceptable here, by design of the platform: HOME and POWER are handled
 * inside the system before dispatch and never reach an accessibility service.
 */
class FLauncherAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "FLauncherA11y"

        /** Sent by the launcher after it edits the mapping table. */
        const val ACTION_RELOAD_MAPPINGS = "me.efesser.flauncher.RELOAD_MAPPINGS"

        /** Sent by the launcher to start/stop "press a button to identify it" mode. */
        const val ACTION_SET_CAPTURE_MODE = "me.efesser.flauncher.SET_CAPTURE_MODE"
        const val EXTRA_CAPTURE_ENABLED = "captureEnabled"

        /** Sent by the launcher when Shizuku permission has just been granted. */
        const val ACTION_REBIND_RAW_INPUT = "me.efesser.flauncher.REBIND_RAW_INPUT"

        /** Broadcast back to the launcher with the button that was pressed. */
        const val ACTION_KEY_CAPTURED = "me.efesser.flauncher.KEY_CAPTURED"
        const val EXTRA_KEY_CODE = "keyCode"
        const val EXTRA_SCAN_CODE = "scanCode"
        const val EXTRA_KEY_LABEL = "keyLabel"
        const val EXTRA_KEY_ACTION = "keyAction"
        const val EXTRA_DEVICE = "device"

        /** Linux key code, present only for events read off /dev/input. */
        const val EXTRA_RAW_CODE = "rawCode"

        /**
         * Held at least this long counts as a long press. The action fires as
         * soon as the timeout elapses rather than on release, which is what a
         * long press feels like everywhere else on the platform.
         */
        private const val LONG_PRESS_MS = 500L

        /** A second press within this window counts as a double press. */
        private const val DOUBLE_PRESS_MS = 300L

        /**
         * Capture mode swallows every button, so a launcher that goes away
         * without disarming it would leave the remote dead. Disarm on our own
         * after this long as a backstop.
         */
        private const val CAPTURE_TIMEOUT_MS = 30_000L

        /**
         * Ignore a repeat of the same app-launch button within this window. The
         * firmware often fires the launch intent more than once per press.
         */
        private const val REDIRECT_DEBOUNCE_MS = 1500L

        /**
         * The OK button that opened the capture dialog also produces an event.
         * Ignore select/enter for a moment after arming so it isn't captured as
         * the button the user meant to map.
         */
        private const val CAPTURE_SELECT_GRACE_MS = 1000L
        private val SELECT_KEY_CODES = setOf(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER)

        /** `value` of a raw EV_KEY event. */
        private const val RAW_UP = 0
        private const val RAW_DOWN = 1

        fun isEnabled(context: Context): Boolean {
            val expected = "${context.packageName}/${FLauncherAccessibilityService::class.java.canonicalName}"
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val splitter = TextUtils.SimpleStringSplitter(':')
            splitter.setString(enabled)
            while (splitter.hasNext()) {
                if (splitter.next().equals(expected, ignoreCase = true)) return true
            }
            return false
        }
    }

    private val handler = Handler(Looper.getMainLooper())

    private var mappings = ButtonMappingStore.Mappings()
    private var captureMode = false
    private var captureArmedAt = 0L

    private var lastRedirectPackage: String? = null
    private var lastRedirectAt = 0L

    // Press-classification state for the button currently held down. heldBinding
    // is what makes an ACTION_UP trustworthy: without a matching ACTION_DOWN the
    // press duration is meaningless, and a stray up would look like a long press.
    private var heldBinding: ButtonMappingStore.Binding? = null
    private var longPressFired = false
    private var pendingLong: Runnable? = null

    private var pendingSingle: Runnable? = null
    private var awaitingSecondPressFor: ButtonMappingStore.Binding? = null

    private val captureTimeout = Runnable { captureMode = false }

    private val preferenceListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == ButtonMappingStore.MAPPINGS_KEY) reloadMappings()
        }

    private val commandReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_RELOAD_MAPPINGS -> reloadMappings()
                ACTION_REBIND_RAW_INPUT -> {
                    AdbInputBridge.resetBackoff()
                    startRawInput()
                }
                ACTION_SET_CAPTURE_MODE -> {
                    captureMode = intent.getBooleanExtra(EXTRA_CAPTURE_ENABLED, false)
                    captureArmedAt = SystemClock.elapsedRealtime()
                    cancelPressState()
                    handler.removeCallbacks(captureTimeout)
                    if (captureMode) handler.postDelayed(captureTimeout, CAPTURE_TIMEOUT_MS)
                }
            }
        }
    }

    private val preferences: SharedPreferences
        get() = getSharedPreferences(ButtonMappingStore.PREFERENCES_NAME, Context.MODE_PRIVATE)

    override fun onServiceConnected() {
        super.onServiceConnected()
        ensureKeyFilteringRequested()
        reloadMappings()
        preferences.registerOnSharedPreferenceChangeListener(preferenceListener)
        val filter = IntentFilter().apply {
            addAction(ACTION_RELOAD_MAPPINGS)
            addAction(ACTION_SET_CAPTURE_MODE)
            addAction(ACTION_REBIND_RAW_INPUT)
        }
        // Not exported: only the launcher process sends these.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(commandReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(commandReceiver, filter)
        }
        // The accessibility service is the one part of the launcher that is
        // always running, so it owns the raw input helper too.
        startRawInput()
        Log.d(TAG, "Button mapper connected")
    }

    /**
     * Brings up whichever route to shell privilege this device has.
     *
     * Shizuku first when it happens to be installed and permitted, since it
     * needs no setup once running. Otherwise the launcher talks to the device's
     * own adbd, which needs nothing installed at all.
     */
    private fun startRawInput() {
        if (ShizukuInputBridge.status() == ShizukuInputBridge.Status.READY) {
            ShizukuInputBridge.start(::onRawKey)
            return
        }
        AdbInputBridge.start(this, ::onRawKey)
    }

    /**
     * A key press read off /dev/input, for the buttons that never reach an app
     * as a key event. Classified with the same single/double/long machinery as
     * an ordinary key, on the same handler.
     */
    private fun onRawKey(code: Int, value: Int, device: String) {
        if (captureMode) {
            broadcastCapturedRawKey(code, value, device)
            return
        }
        val binding = mappings.rawBindings[code] ?: return
        when (value) {
            RAW_DOWN -> onBindingDown(binding, repeat = false)
            RAW_UP -> onBindingUp(binding)
            // RAW_REPEAT says nothing new; the long press is already scheduled.
        }
    }

    /**
     * Re-declares the key filtering flag at runtime.
     *
     * The manifest metadata is meant to be enough, but a fair number of TV
     * firmwares drop the flag when the service reconnects, after which
     * [onKeyEvent] is simply never called again. Setting it back on every
     * connect costs nothing and is what other button mappers do.
     */
    private fun ensureKeyFilteringRequested() {
        val info = serviceInfo ?: return
        val wanted = AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        if (info.flags and wanted != 0) return
        info.flags = info.flags or wanted
        try {
            serviceInfo = info
        } catch (e: Exception) {
            Log.w(TAG, "Could not request key event filtering", e)
        }
    }

    override fun onUnbind(intent: Intent?): Boolean {
        ShizukuInputBridge.stop()
        AdbInputBridge.stop()
        cancelPressState()
        handler.removeCallbacks(captureTimeout)
        preferences.unregisterOnSharedPreferenceChangeListener(preferenceListener)
        try {
            unregisterReceiver(commandReceiver)
        } catch (e: IllegalArgumentException) {
            // Never registered; nothing to do.
        }
        return super.onUnbind(intent)
    }

    private fun reloadMappings() {
        mappings = ButtonMappingStore.load(this)
        Log.d(
            TAG,
            "Loaded ${mappings.bindings.size} button bindings, " +
                "${mappings.appRedirects.size} app redirects",
        )
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (captureMode) return handleCapture(event)

        val binding = mappings.resolve(event.keyCode, event.scanCode)
            ?: return super.onKeyEvent(event)

        when (event.action) {
            KeyEvent.ACTION_DOWN -> onBindingDown(binding, event.repeatCount > 0)
            KeyEvent.ACTION_UP -> onBindingUp(binding)
        }
        // Consume down and up alike, so the foreground app sees neither.
        return true
    }

    private fun onBindingDown(binding: ButtonMappingStore.Binding, repeat: Boolean) {
        // Auto-repeat from holding the button; the long press is already
        // scheduled from the original press.
        if (repeat) return

        // Pressing a different button settles the question of whether the
        // previous one was a double press, so run its single action now instead
        // of making the user wait out the rest of the window.
        if (awaitingSecondPressFor != null && awaitingSecondPressFor != binding) flushPendingSingle()
        cancelPendingLong()

        heldBinding = binding
        longPressFired = false
        if (!binding.hasLong) return

        val runnable = Runnable {
            pendingLong = null
            longPressFired = true
            // The long press supersedes a single that was waiting for a double.
            cancelPendingSingle()
            perform(binding.actionFor(ButtonMappingStore.Trigger.LONG))
        }
        pendingLong = runnable
        handler.postDelayed(runnable, LONG_PRESS_MS)
    }

    private fun onBindingUp(binding: ButtonMappingStore.Binding) {
        cancelPendingLong()

        // Already handled while the button was still held.
        if (longPressFired) {
            longPressFired = false
            heldBinding = null
            return
        }

        // No matching down means the press started before this binding existed,
        // or the down went elsewhere; there is nothing to classify.
        if (heldBinding != binding) return
        heldBinding = null

        // A second press landing inside the double-press window wins outright.
        if (awaitingSecondPressFor == binding) {
            cancelPendingSingle()
            perform(binding.actionFor(ButtonMappingStore.Trigger.DOUBLE))
            return
        }

        // Only pay the double-press latency when a double action is configured.
        if (!binding.hasDouble) {
            perform(binding.actionFor(ButtonMappingStore.Trigger.SINGLE))
            return
        }

        awaitingSecondPressFor = binding
        val runnable = Runnable {
            awaitingSecondPressFor = null
            pendingSingle = null
            perform(binding.actionFor(ButtonMappingStore.Trigger.SINGLE))
        }
        pendingSingle = runnable
        handler.postDelayed(runnable, DOUBLE_PRESS_MS)
    }

    private fun cancelPendingSingle() {
        pendingSingle?.let { handler.removeCallbacks(it) }
        pendingSingle = null
        awaitingSecondPressFor = null
    }

    /** Runs a single-press action that is still waiting out the double window. */
    private fun flushPendingSingle() {
        val runnable = pendingSingle ?: return
        handler.removeCallbacks(runnable)
        // The runnable clears pendingSingle and awaitingSecondPressFor itself.
        runnable.run()
    }

    private fun cancelPendingLong() {
        pendingLong?.let { handler.removeCallbacks(it) }
        pendingLong = null
    }

    private fun cancelPressState() {
        cancelPendingSingle()
        cancelPendingLong()
        heldBinding = null
        longPressFired = false
    }

    /**
     * Swallows everything while learning, so the button under test does not also
     * trigger its normal behaviour, and reports it to the launcher.
     */
    private fun handleCapture(event: KeyEvent): Boolean {
        // Back has to keep working, otherwise the dialog that armed capture mode
        // cannot be closed — capture swallows everything else. The cost is that
        // Back itself cannot be mapped.
        if (event.keyCode == KeyEvent.KEYCODE_BACK) return false

        // Auto-repeat from a held button says nothing new.
        if (event.repeatCount > 0) return true
        if (event.keyCode in SELECT_KEY_CODES &&
            SystemClock.elapsedRealtime() - captureArmedAt < CAPTURE_SELECT_GRACE_MS
        ) {
            // This is the OK press that opened the dialog, not a real answer.
            return true
        }
        // Both edges are reported: the button test screen shows everything the
        // service can see, and some remote buttons only ever send a down.
        broadcastCapturedKey(event)
        return true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        if (mappings.appRedirects.isEmpty()) return

        val packageName = event.packageName?.toString() ?: return
        val action = mappings.appRedirects[packageName] ?: return

        val now = SystemClock.elapsedRealtime()
        if (packageName == lastRedirectPackage && now - lastRedirectAt < REDIRECT_DEBOUNCE_MS) return
        lastRedirectPackage = packageName
        lastRedirectAt = now

        // Send the offending app back before launching the replacement,
        // otherwise it stays underneath on the back stack.
        performGlobalAction(GLOBAL_ACTION_BACK)
        perform(action)
    }

    override fun onInterrupt() {}

    private fun broadcastCapturedKey(event: KeyEvent) {
        Log.d(
            TAG,
            "captured action=${event.action} keyCode=${event.keyCode} " +
                "scanCode=${event.scanCode} device=${event.device?.name}",
        )
        val intent = Intent(ACTION_KEY_CAPTURED).apply {
            setPackage(packageName)
            putExtra(EXTRA_KEY_CODE, event.keyCode)
            putExtra(EXTRA_SCAN_CODE, event.scanCode)
            putExtra(EXTRA_KEY_LABEL, KeyEvent.keyCodeToString(event.keyCode))
            putExtra(EXTRA_KEY_ACTION, event.action)
            putExtra(EXTRA_DEVICE, event.device?.name ?: "")
        }
        sendBroadcast(intent)
    }

    /** Same channel as a captured key, flagged so the UI can tell them apart. */
    private fun broadcastCapturedRawKey(code: Int, value: Int, device: String) {
        if (value != RAW_DOWN && value != RAW_UP) return
        Log.d(TAG, "captured raw code=$code value=$value device=$device")
        val intent = Intent(ACTION_KEY_CAPTURED).apply {
            setPackage(packageName)
            putExtra(EXTRA_KEY_CODE, KeyEvent.KEYCODE_UNKNOWN)
            putExtra(EXTRA_SCAN_CODE, 0)
            putExtra(EXTRA_KEY_LABEL, "RAW")
            putExtra(EXTRA_KEY_ACTION, if (value == RAW_DOWN) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP)
            putExtra(EXTRA_DEVICE, device)
            putExtra(EXTRA_RAW_CODE, code)
        }
        sendBroadcast(intent)
    }

    private fun perform(action: ButtonMappingStore.Action?) {
        when (action) {
            is ButtonMappingStore.Action.LaunchApp -> launchPackage(action.packageName)
            ButtonMappingStore.Action.OpenFlauncher -> launchPackage(packageName)
            ButtonMappingStore.Action.OpenSettings -> startActivitySafely(
                Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            // Block, or nothing bound to this trigger: the event was already
            // consumed, which is the whole point.
            ButtonMappingStore.Action.Block, null -> Unit
        }
    }

    private fun launchPackage(target: String) {
        val intent = packageManager.getLeanbackLaunchIntentForPackage(target)
            ?: packageManager.getLaunchIntentForPackage(target)
        if (intent == null) {
            Log.w(TAG, "No launch intent for $target")
            return
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        startActivitySafely(intent)
    }

    private fun startActivitySafely(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Could not start $intent", e)
        }
    }
}
