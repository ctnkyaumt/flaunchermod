/*
 * FLaunchermod
 * originally by efesser (30 May 2021)
 * ctnkyaumt 2026
 * Copyright (C) 2026 - ctnkyaumt
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package me.efesser.flauncher

/** Keeps the hardware usage that distinguishes vendor buttons sharing EV_KEY. */
internal class RawKeyDecoder {
    data class Key(val code: Int, val value: Int, val device: String, val scanCode: Int)

    private val frameScans = mutableMapOf<String, Int>()
    private val heldScans = mutableMapOf<Pair<String, Int>, Int>()
    private val droppedDevices = mutableSetOf<String>()

    fun acceptLine(line: String): Key? {
        val match = EVENT_LINE.matchEntire(line.trim()) ?: return null
        val type = match.groupValues[2].toIntOrNull(16) ?: return null
        val code = match.groupValues[3].toIntOrNull(16) ?: return null
        // getevent prints signed int32 values as unsigned hex, including
        // vendor usages with the high bit set.
        val value = match.groupValues[4].toLongOrNull(16)
            ?.takeIf { it <= 0xffffffffL }?.toInt() ?: return null
        return accept(match.groupValues[1], type, code, value)
    }

    fun accept(device: String, type: Int, code: Int, value: Int): Key? {
        if (type == EV_SYN && code == SYN_DROPPED) {
            frameScans.remove(device)
            heldScans.keys.removeAll { it.first == device }
            droppedDevices.add(device)
            return null
        }
        if (device in droppedDevices) {
            if (type == EV_SYN && code == SYN_REPORT) droppedDevices.remove(device)
            return null
        }
        when {
            type == EV_MSC && code == MSC_SCAN -> frameScans[device] = value
            type == EV_SYN && code == SYN_REPORT -> frameScans.remove(device)
            type == EV_KEY && value in 0..2 -> {
                val identity = device to code
                // IR drivers often omit MSC_SCAN on release and autorepeat.
                // A new down without MSC_SCAN must not inherit a previous key.
                val scanCode = frameScans.remove(device)
                    ?: if (value != 1) heldScans[identity] ?: 0 else 0
                when (value) {
                    1 -> heldScans[identity] = scanCode
                    0 -> heldScans.remove(identity)
                }
                return Key(code, value, device, scanCode)
            }
        }
        return null
    }

    private companion object {
        /** `getevent -q` prints `/dev/input/eventN: TYPE CODE VALUE`, all hex. */
        val EVENT_LINE = Regex("^(\\S+):\\s+([0-9a-fA-F]+)\\s+([0-9a-fA-F]+)\\s+([0-9a-fA-F]+)$")
        const val EV_SYN = 0x00
        const val EV_KEY = 0x01
        const val EV_MSC = 0x04
        const val SYN_REPORT = 0x00
        const val SYN_DROPPED = 0x03
        const val MSC_SCAN = 0x04
    }
}
