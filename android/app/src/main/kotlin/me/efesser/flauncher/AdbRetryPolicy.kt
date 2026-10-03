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

/** A successful handshake is not evidence that the input stream is usable. */
internal class AdbRetryPolicy {
    companion object {
        private val DELAYS_MS = longArrayOf(5_000, 15_000, 30_000, 60_000, 120_000)
        private const val MAX_RETRIES = 12
        private const val STABLE_STREAM_MS = 30_000L
    }

    private var retries = 0

    fun reset() {
        retries = 0
    }

    /** Reset only after a stream survives, including an idle getevent stream. */
    fun nextDelay(connectedForMs: Long): Long? {
        if (connectedForMs >= STABLE_STREAM_MS) reset()
        if (retries >= MAX_RETRIES) return null
        return DELAYS_MS[retries.coerceAtMost(DELAYS_MS.lastIndex)].also { retries++ }
    }
}
