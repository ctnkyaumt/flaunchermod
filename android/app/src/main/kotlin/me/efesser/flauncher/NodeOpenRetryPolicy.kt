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

/**
 * How long to keep trying to open an input node that failed to open.
 *
 * A remote that reconnects gets a fresh `/dev/input/eventN` node, and Android
 * sets its permissions a moment after the node appears, so the first open can
 * fail on a node that becomes readable a few hundred milliseconds later. One
 * instance belongs to one node; it allows a small, fixed number of retries.
 */
internal class NodeOpenRetryPolicy {
    companion object {
        private val DELAYS_MS = longArrayOf(100, 250, 500, 1_000, 2_000)
    }

    private var retries = 0

    /** Milliseconds to wait before the next attempt, or null to give up. */
    fun nextDelay(): Long? {
        if (retries >= DELAYS_MS.size) return null
        return DELAYS_MS[retries++]
    }
}
