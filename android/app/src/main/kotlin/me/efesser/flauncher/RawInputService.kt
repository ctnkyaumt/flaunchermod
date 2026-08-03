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

        private const val EV_KEY = 0x01

        /**
         * `struct input_event` is a `timeval` followed by u16 type, u16 code and
         * s32 value. `timeval` holds two longs, so the struct is 24 bytes in a
         * 64-bit process and 16 in a 32-bit one.
         */
        private val EVENT_SIZE =
            if (System.getProperty("os.arch")?.contains("64") == true) 24 else 16
        private val TIME_SIZE = EVENT_SIZE - 8
    }

    private val streams = mutableListOf<FileInputStream>()
    private val opened = mutableListOf<String>()

    @Volatile
    private var callback: IRawInputCallback? = null

    @Volatile
    private var running = false

    override fun start(callback: IRawInputCallback?) {
        stop()
        if (callback == null) return
        this.callback = callback
        running = true

        val nodes = File("/dev/input")
            .listFiles { file -> file.name.startsWith("event") }
            ?.sortedBy { it.name }
            ?: emptyList()

        for (node in nodes) {
            val stream = try {
                FileInputStream(node)
            } catch (e: Exception) {
                // Not every node is readable, and most are not keyboards.
                Log.d(TAG, "Skipping ${node.path}: ${e.message}")
                continue
            }
            streams.add(stream)
            opened.add(node.path)
            thread(name = "raw-input-${node.name}", isDaemon = true) { pump(stream, node.path) }
        }
        Log.d(TAG, "Reading ${opened.size} of ${nodes.size} input nodes, struct $EVENT_SIZE bytes")
    }

    private fun pump(stream: FileInputStream, path: String) {
        val buffer = ByteArray(EVENT_SIZE)
        while (running) {
            try {
                var read = 0
                while (read < EVENT_SIZE) {
                    val count = stream.read(buffer, read, EVENT_SIZE - read)
                    if (count < 0) return
                    read += count
                }
            } catch (e: Exception) {
                // Closed by stop(), or the device went away.
                return
            }

            val wrapped = ByteBuffer.wrap(buffer).order(ByteOrder.nativeOrder())
            if ((wrapped.getShort(TIME_SIZE).toInt() and 0xFFFF) != EV_KEY) continue
            val code = wrapped.getShort(TIME_SIZE + 2).toInt() and 0xFFFF
            val value = wrapped.getInt(TIME_SIZE + 4)

            try {
                callback?.onRawKey(code, value, path)
            } catch (e: Exception) {
                // The launcher went away; nothing left to report to.
                return
            }
        }
    }

    override fun stop() {
        running = false
        callback = null
        for (stream in streams) {
            try {
                stream.close()
            } catch (e: Exception) {
                // Already gone.
            }
        }
        streams.clear()
        opened.clear()
    }

    override fun openedDevices(): MutableList<String> = opened.toMutableList()

    override fun destroy() {
        stop()
        exitProcess(0)
    }
}
