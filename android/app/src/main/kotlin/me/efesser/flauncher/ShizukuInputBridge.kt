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

import android.content.ComponentName
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import rikka.shizuku.Shizuku

/**
 * Owns the connection to [RawInputService].
 *
 * Shizuku is the only route an ordinary app has to shell privilege, and shell
 * privilege is the only route to `/dev/input`. Everything here degrades quietly:
 * with no Shizuku installed, or permission not granted, the launcher works as
 * before and only the raw button bindings stop firing.
 */
object ShizukuInputBridge {

    private const val TAG = "FLauncherShizuku"
    const val PERMISSION_REQUEST_CODE = 4301

    /** What the settings page shows about the connection. */
    enum class Status { UNAVAILABLE, PERMISSION_REQUIRED, READY }

    fun interface RawKeyListener {
        fun onRawKey(code: Int, value: Int, device: String)
    }

    private val handler = Handler(Looper.getMainLooper())

    private var service: IRawInputService? = null
    private var listener: RawKeyListener? = null
    private var wantRunning = false

    /** Nodes the helper managed to open, for the diagnostics screen. */
    @Volatile
    var openedDevices: List<String> = emptyList()
        private set

    private val callback = object : IRawInputCallback.Stub() {
        override fun onRawKey(code: Int, value: Int, device: String?) {
            val target = listener ?: return
            // Arrives on a binder thread; everything downstream expects main.
            handler.post { target.onRawKey(code, value, device ?: "") }
        }
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            if (binder == null || !binder.pingBinder()) {
                Log.w(TAG, "Helper bound with a dead binder")
                return
            }
            val bound = IRawInputService.Stub.asInterface(binder)
            service = bound
            try {
                bound.start(callback)
                openedDevices = bound.openedDevices() ?: emptyList()
                Log.d(TAG, "Helper reading ${openedDevices.size} nodes")
            } catch (e: Exception) {
                Log.w(TAG, "Could not start the helper", e)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            openedDevices = emptyList()
        }
    }

    private val binderReceived = Shizuku.OnBinderReceivedListener {
        // Shizuku often starts after us; pick the connection back up then.
        if (wantRunning) handler.post { start(listener) }
    }

    private val binderDead = Shizuku.OnBinderDeadListener {
        service = null
        openedDevices = emptyList()
    }

    private var listenersRegistered = false

    private val userServiceArgs
        get() = Shizuku.UserServiceArgs(
            ComponentName(BuildConfig.APPLICATION_ID, RawInputService::class.java.name)
        )
            .daemon(false)
            .processNameSuffix("rawinput")
            .debuggable(false)
            .version(1)

    fun status(): Status = try {
        when {
            !Shizuku.pingBinder() -> Status.UNAVAILABLE
            Shizuku.isPreV11() -> Status.UNAVAILABLE
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED -> Status.READY
            else -> Status.PERMISSION_REQUIRED
        }
    } catch (e: Exception) {
        Status.UNAVAILABLE
    }

    /** Must be called from an activity; Shizuku shows its own consent dialog. */
    fun requestPermission(): Boolean = try {
        if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
            true
        } else {
            Shizuku.requestPermission(PERMISSION_REQUEST_CODE)
            false
        }
    } catch (e: Exception) {
        Log.w(TAG, "Could not ask for Shizuku permission", e)
        false
    }

    /**
     * Binds the helper and routes raw key events to [listener]. Safe to call
     * repeatedly; a second call just swaps the listener.
     */
    fun start(listener: RawKeyListener?) {
        this.listener = listener
        wantRunning = true

        if (!listenersRegistered) {
            listenersRegistered = true
            try {
                Shizuku.addBinderReceivedListenerSticky(binderReceived)
                Shizuku.addBinderDeadListener(binderDead)
            } catch (e: Exception) {
                Log.w(TAG, "Could not observe Shizuku", e)
            }
        }

        if (status() != Status.READY) {
            Log.d(TAG, "Shizuku not ready (${status()}); raw input stays off")
            return
        }
        if (service != null) return

        try {
            Shizuku.bindUserService(userServiceArgs, connection)
        } catch (e: Exception) {
            Log.w(TAG, "Could not bind the raw input helper", e)
        }
    }

    fun stop() {
        wantRunning = false
        listener = null
        try {
            service?.stop()
        } catch (e: Exception) {
            // Already gone.
        }
        try {
            Shizuku.unbindUserService(userServiceArgs, connection, true)
        } catch (e: Exception) {
            // Never bound.
        }
        service = null
        openedDevices = emptyList()
    }
}
