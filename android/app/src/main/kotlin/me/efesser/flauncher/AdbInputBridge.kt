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

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit
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

    private const val LOOPBACK = "127.0.0.1"

    /** The port `adb tcpip 5555` opens. Nothing listens there by default. */
    private const val LEGACY_PORT = 5555

    private const val MDNS_TIMEOUT_MS = 7_000L
    private const val CONNECT_TIMEOUT_MS = 15_000L

    private const val LOG_FIRST_LINES = 12

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

    @Volatile
    private var listener: ShizukuInputBridge.RawKeyListener? = null
    private val connectionLock = Any()
    @Volatile
    private var reader: Thread? = null
    @Volatile
    private var generation = 0

    @Volatile
    var state: State = State.DISCONNECTED
        private set

    /** Last thing that went wrong, shown on the settings page. */
    @Volatile
    var lastError: String? = null
        private set

    @Volatile
    private var running = false

    private val retryPolicy = AdbRetryPolicy()
    private var pendingRetry: Runnable? = null

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
    /** Clears the backoff so a user pressing Connect gets an immediate try. */
    fun resetBackoff() {
        retryPolicy.reset()
        pendingRetry?.let { handler.removeCallbacks(it) }
        pendingRetry = null
        if (state == State.FAILED) state = State.DISCONNECTED
    }

    fun start(context: Context, listener: ShizukuInputBridge.RawKeyListener?) {
        this.listener = listener
        if (state == State.CONNECTED || state == State.CONNECTING || state == State.FAILED) return
        pendingRetry?.let { handler.removeCallbacks(it) }
        pendingRetry = null
        state = State.CONNECTING
        running = true
        val session = ++generation
        val appContext = context.applicationContext

        val worker = thread(name = "adb-getevent", isDaemon = true, start = false) {
            // The manager is a singleton. Finish closing the previous session
            // before a replacement reader can open another connection on it.
            synchronized(connectionLock) {
                if (!isCurrent(session)) return@synchronized
                var connection: AbsAdbConnectionManager? = null
                var connectedAt: Long? = null
                var retryAllowed = true
                try {
                    connection = AdbConnectionManager.getInstance(appContext)
                    connection.setHostAddress(LOOPBACK)
                    connection.setTimeout(CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    connect(connection, appContext, session)
                    if (!isCurrent(session)) return@synchronized
                    Log.d(TAG, "Connected to local adbd")
                    try {
                        pump(connection, session) {
                            connectedAt = SystemClock.elapsedRealtime()
                            handler.post {
                                if (isCurrent(session)) {
                                    state = State.CONNECTED
                                    lastError = null
                                }
                            }
                        }
                    } catch (e: RuntimeException) {
                        // Reconnecting cannot repair a broken input reader. It
                        // can, however, repeatedly reopen Android's auth dialog.
                        retryAllowed = false
                        throw e
                    }
                } catch (e: Exception) {
                    if (isCurrent(session)) {
                        handler.post {
                            if (isCurrent(session)) lastError = describe(e)
                        }
                        Log.w(TAG, "Could not read input over ADB", e)
                    }
                } catch (e: LinkageError) {
                    retryAllowed = false
                    if (isCurrent(session)) {
                        handler.post {
                            if (isCurrent(session)) lastError = e.message ?: e.javaClass.simpleName
                        }
                        Log.e(TAG, "ADB library is incompatible with this device", e)
                    }
                } finally {
                    try {
                        // close() also destroys the singleton's authentication
                        // key; disconnect() keeps it usable for the next try.
                        connection?.disconnect()
                    } catch (e: Exception) {
                        // Already gone.
                    } catch (e: LinkageError) {
                        retryAllowed = false
                        Log.e(TAG, "ADB library failed during disconnect", e)
                        handler.post {
                            if (isCurrent(session)) lastError = e.message ?: e.javaClass.simpleName
                        }
                    }
                    if (reader === Thread.currentThread()) reader = null
                    val connectedForMs = connectedAt?.let { SystemClock.elapsedRealtime() - it } ?: 0L
                    handler.post {
                        if (isCurrent(session)) {
                            if (retryAllowed) scheduleRetry(appContext, session, connectedForMs)
                            else state = State.FAILED
                        }
                    }
                }
            }
        }
        reader = worker
        worker.start()
    }

    private fun isCurrent(session: Int): Boolean = running && generation == session

    private fun connect(connection: AbsAdbConnectionManager, context: Context, session: Int) {
        // Many TVs expose only the legacy TCP port, even on Android 11+.
        // libadb throws on an mDNS timeout instead of returning false, so it
        // must not prevent the direct connection from being attempted.
        val directError = try {
            if (connection.isConnected || connection.connect(LOOPBACK, LEGACY_PORT)) return
            IllegalStateException("adbd did not authorise the connection in time")
        } catch (e: Exception) {
            e
        }
        if (!isCurrent(session)) throw InterruptedException("ADB reader stopped")
        connection.disconnect()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                if (connection.autoConnect(context, MDNS_TIMEOUT_MS)) return
            } catch (e: Exception) {
                if (!isCurrent(session)) throw e
                // A discovery timeout carries no useful setup advice. Preserve
                // the direct-port failure unless discovery found an auth issue.
                if (e !is InterruptedException) throw e
            }
        }
        throw directError
    }

    /**
     * Retries with a backoff. At boot the accessibility service is up before
     * adbd has opened its socket, so the first attempt usually loses the race.
     */
    private fun scheduleRetry(context: Context, session: Int, connectedForMs: Long) {
        state = State.DISCONNECTED
        val delay = retryPolicy.nextDelay(connectedForMs)
        if (delay == null) {
            state = State.FAILED
            return
        }
        val retry = Runnable {
            pendingRetry = null
            if (isCurrent(session)) start(context.applicationContext, listener)
        }
        pendingRetry = retry
        handler.postDelayed(retry, delay)
    }

    private fun pump(connection: AbsAdbConnectionManager, session: Int, onStreamOpened: () -> Unit) {
        // -q drops the device listing, leaving only the events themselves.
        connection.openStream("shell:getevent -q").use { stream ->
            Log.d(TAG, "getevent stream open")
            onStreamOpened()
            var seen = 0
            val decoder = RawKeyDecoder()
            BufferedReader(InputStreamReader(stream.openInputStream())).use { input ->
                while (isCurrent(session)) {
                    val line = input.readLine() ?: break
                    // The first handful verbatim makes unexpected formats clear.
                    if (seen < LOG_FIRST_LINES) {
                        seen++
                        Log.d(TAG, "getevent[$seen]: $line")
                    }
                    val key = decoder.acceptLine(line) ?: continue
                    Log.d(TAG, "raw key code=${key.code} scan=${key.scanCode} value=${key.value} device=${key.device}")
                    val target = listener ?: continue
                    handler.post {
                        if (isCurrent(session) && listener === target) {
                            target.onRawKey(key.code, key.value, key.device, key.scanCode)
                        }
                    }
                }
            }
        }
        Log.d(TAG, "getevent stream ended")
    }

    fun stop() {
        running = false
        generation++
        listener = null
        retryPolicy.reset()
        handler.removeCallbacksAndMessages(null)
        pendingRetry = null
        // Interrupt reads/handshakes; the worker closes its stream and manager
        // off the main thread, then lets any replacement session proceed.
        reader?.interrupt()
        state = State.DISCONNECTED
    }
}
