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

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.concurrent.thread

/**
 * Reads remote buttons through the device's own adbd, over loopback.
 *
 * The alternative, Shizuku, needs a second app installed and restarted after
 * every reboot. adbd is already on the device: with wireless debugging turned
 * on, the launcher can authenticate to it as an ordinary ADB client and run
 * `getevent`, which prints every kernel input event. That is the same privilege
 * Shizuku hands out, obtained without anything else installed.
 *
 * The user authorises the launcher's key once — by accepting the debugging
 * prompt, or by typing a pairing code on Android 11 and later — and adbd
 * remembers it.
 */
object AdbInputBridge {

    private const val TAG = "FLauncherAdb"

    /** `getevent` prints `/dev/input/eventN: TYPE CODE VALUE`, all hex. */
    private val EVENT_LINE = Regex("^(\\S+):\\s+([0-9a-fA-F]+)\\s+([0-9a-fA-F]+)\\s+([0-9a-fA-F]+)")

    private const val EV_KEY = 0x01

    private const val LOOPBACK = "127.0.0.1"

    /** The port `adb tcpip 5555` opens. Nothing listens there by default. */
    private const val LEGACY_PORT = 5555

    private const val MDNS_TIMEOUT_MS = 7_000L

    /**
     * adbd not listening is by far the most common failure, and the message the
     * exception carries for it says nothing useful. Name the fix instead.
     */
    private fun describe(e: Exception): String = when {
        e is java.net.ConnectException ||
            e is java.net.SocketTimeoutException ||
            e.message?.contains("ECONNREFUSED", ignoreCase = true) == true ->
            "adbd is not listening on TCP. Run `adb tcpip 5555` once from a computer."
        e.javaClass.simpleName.contains("PairingRequired") ->
            "This device wants a pairing code first."
        else -> e.message ?: e.javaClass.simpleName
    }

    enum class State { DISCONNECTED, CONNECTING, CONNECTED, FAILED }

    private val handler = Handler(Looper.getMainLooper())

    private var listener: ShizukuInputBridge.RawKeyListener? = null
    private var manager: AbsAdbConnectionManager? = null
    private var reader: Thread? = null

    @Volatile
    var state: State = State.DISCONNECTED
        private set

    /** Last thing that went wrong, shown on the settings page. */
    @Volatile
    var lastError: String? = null
        private set

    @Volatile
    private var running = false

    /** Whether the device needs a pairing code before it will accept a key. */
    val pairingSupported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    /**
     * Pairs with the local adbd. Android 11 and later only, where wireless
     * debugging shows a pairing code and its own port.
     */
    fun pair(context: Context, port: Int, code: String): Boolean = try {
        AdbConnectionManager.getInstance(context).pair("127.0.0.1", port, code)
    } catch (e: Exception) {
        lastError = e.message ?: e.javaClass.simpleName
        Log.w(TAG, "Pairing failed", e)
        false
    }

    /**
     * Connects and starts reporting key events. Safe to call again; a second
     * call replaces the listener and reconnects only if needed.
     */
    fun start(context: Context, listener: ShizukuInputBridge.RawKeyListener?) {
        this.listener = listener
        if (state == State.CONNECTED || state == State.CONNECTING) return
        state = State.CONNECTING
        running = true

        thread(name = "adb-getevent", isDaemon = true) {
            try {
                val connection = AdbConnectionManager.getInstance(context)
                connection.setHostAddress(LOOPBACK)
                manager = connection

                val connected = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Wireless debugging picks a random port and announces it
                    // over mDNS; there is no fixed one to guess.
                    connection.autoConnect(context, MDNS_TIMEOUT_MS) ||
                        connection.connect(LOOPBACK, LEGACY_PORT)
                } else {
                    // No mDNS before Android 11. adbd only listens on TCP once
                    // someone has set service.adb.tcp.port, which is what
                    // `adb tcpip 5555` does.
                    connection.connect(LOOPBACK, LEGACY_PORT)
                }

                if (!connected) {
                    throw IllegalStateException("adbd refused the connection")
                }
                state = State.CONNECTED
                lastError = null
                Log.d(TAG, "Connected to local adbd")
                pump(connection)
            } catch (e: Exception) {
                lastError = describe(e)
                state = State.FAILED
                Log.w(TAG, "Could not read input over ADB", e)
            }
        }
    }

    private fun pump(connection: AbsAdbConnectionManager) {
        // -q drops the device listing, leaving only the events themselves.
        val stream = connection.openStream("shell:getevent -q")
        reader = Thread.currentThread()
        BufferedReader(InputStreamReader(stream.openInputStream())).use { input ->
            while (running) {
                val line = input.readLine() ?: break
                val match = EVENT_LINE.find(line.trim()) ?: continue
                val type = match.groupValues[2].toIntOrNull(16) ?: continue
                if (type != EV_KEY) continue
                val code = match.groupValues[3].toIntOrNull(16) ?: continue
                val value = match.groupValues[4].toIntOrNull(16) ?: continue
                val device = match.groupValues[1]

                val target = listener ?: continue
                handler.post { target.onRawKey(code, value, device) }
            }
        }
        state = State.DISCONNECTED
    }

    fun stop() {
        running = false
        listener = null
        try {
            manager?.close()
        } catch (e: Exception) {
            // Already gone.
        }
        manager = null
        state = State.DISCONNECTED
    }
}
