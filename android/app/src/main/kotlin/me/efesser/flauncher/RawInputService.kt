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

import android.os.FileObserver
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread
import kotlin.system.exitProcess

/**
 * Reads remote button presses straight off the kernel input devices.
 *
 * Runs inside a process Shizuku starts for us, which means it runs as `shell` —
 * a member of the `input` group, so it can open `/dev/input/event*`. The
 * launcher process cannot: those nodes are `0660 root:input`.
 *
 * This is the only way to see the buttons the firmware wires directly to an app
 * launch. They never become key events, so an accessibility service is blind to
 * them no matter what flags it asks for; at the kernel level they are ordinary
 * key presses like any other.
 *
 * Nothing is suppressed here. Grabbing a device exclusively needs an `ioctl`
 * and therefore native code, and it is not necessary for the case this exists
 * for: the app the button launches is disabled, so the firmware's own handling
 * already does nothing.
 */
class RawInputService : IRawInputService.Stub() {

    companion object {
        private const val TAG = "FLauncherRawInput"

        private val INPUT_DIRECTORY = File("/dev/input")

        /**
         * `struct input_event` is a `timeval` followed by u16 type, u16 code and
         * s32 value. `timeval` holds two longs, so the struct is 24 bytes in a
         * 64-bit process and 16 in a 32-bit one.
         */
        private val EVENT_SIZE =
            if (System.getProperty("os.arch")?.contains("64") == true) 24 else 16
        private val TIME_SIZE = EVENT_SIZE - 8
    }

    private val streamLock = Any()
    private val streams = mutableMapOf<String, FileInputStream>()
    private var inputObserver: FileObserver? = null

    @Volatile
    private var callback: IRawInputCallback? = null

    @Volatile
    private var running = false

    override fun start(callback: IRawInputCallback?) {
        stop()
        if (callback == null) return
        this.callback = callback
        running = true

        // Start watching before the initial scan so a Bluetooth remote cannot
        // appear in the gap and remain invisible until the service restarts.
        inputObserver = object : FileObserver(
            INPUT_DIRECTORY.path,
            FileObserver.CREATE or FileObserver.MOVED_TO or
                FileObserver.DELETE or FileObserver.MOVED_FROM,
        ) {
            override fun onEvent(event: Int, path: String?) {
                if (!running || path == null || !path.startsWith("event")) return
                when {
                    event and (FileObserver.CREATE or FileObserver.MOVED_TO) != 0 ->
                        openNode(File(INPUT_DIRECTORY, path))
                    event and (FileObserver.DELETE or FileObserver.MOVED_FROM) != 0 ->
                        closeNode(File(INPUT_DIRECTORY, path).path)
                }
            }
        }.also { it.startWatching() }

        val nodes = INPUT_DIRECTORY
            .listFiles { file -> file.name.startsWith("event") }
            ?.sortedBy { it.name }
            ?: emptyList()

        nodes.forEach(::openNode)
        Log.d(
            TAG,
            "Reading ${openedDevices().size} of ${nodes.size} input nodes, struct $EVENT_SIZE bytes",
        )
    }

    /** Opens one event node once and starts its reader. */
    private fun openNode(node: File) {
        val path = node.path
        synchronized(streamLock) {
            if (!running || streams.containsKey(path)) return
        }

        val stream = try {
            FileInputStream(node)
        } catch (e: Exception) {
            // Not every node is readable, and most are not keyboards.
            Log.d(TAG, "Skipping $path: ${e.message}")
            return
        }

        synchronized(streamLock) {
            if (!running || streams.containsKey(path)) {
                stream.close()
                return
            }
            streams[path] = stream
        }
        Log.d(TAG, "Opened $path")
        thread(name = "raw-input-${node.name}", isDaemon = true) { pump(stream, path) }
    }

    private fun closeNode(path: String) {
        val stream = synchronized(streamLock) { streams.remove(path) } ?: return
        try {
            stream.close()
        } catch (e: Exception) {
            // Already closed by the reader.
        }
        Log.d(TAG, "Closed $path")
    }

    private fun pump(stream: FileInputStream, path: String) {
        val buffer = ByteArray(EVENT_SIZE)
        val decoder = RawKeyDecoder()
        try {
            while (running && synchronized(streamLock) { streams[path] === stream }) {
                var read = 0
                while (read < EVENT_SIZE) {
                    val count = stream.read(buffer, read, EVENT_SIZE - read)
                    if (count < 0) return
                    read += count
                }

                val wrapped = ByteBuffer.wrap(buffer).order(ByteOrder.nativeOrder())
                val type = wrapped.getShort(TIME_SIZE).toInt() and 0xFFFF
                val code = wrapped.getShort(TIME_SIZE + 2).toInt() and 0xFFFF
                val value = wrapped.getInt(TIME_SIZE + 4)

                val key = decoder.accept(path, type, code, value) ?: continue
                // Ignore an old reader finishing after stop()/start().
                synchronized(streamLock) {
                    if (running && streams[path] === stream) {
                        callback?.onRawKey(key.code, key.value, key.device, key.scanCode)
                    }
                }
            }
        } catch (e: Exception) {
            // Closed by stop(), the device went away, or the callback died.
        } finally {
            synchronized(streamLock) {
                if (streams[path] === stream) streams.remove(path)
            }
            try {
                stream.close()
            } catch (e: Exception) {
                // Already closed.
            }
        }
    }

    override fun stop() {
        running = false
        callback = null
        inputObserver?.stopWatching()
        inputObserver = null
        val toClose = synchronized(streamLock) {
            streams.values.toList().also { streams.clear() }
        }
        for (stream in toClose) {
            try {
                stream.close()
            } catch (e: Exception) {
                // Already gone.
            }
        }
    }

    override fun openedDevices(): MutableList<String> = synchronized(streamLock) {
        streams.keys.sorted().toMutableList()
    }

    override fun destroy() {
        stop()
        exitProcess(0)
    }
}
