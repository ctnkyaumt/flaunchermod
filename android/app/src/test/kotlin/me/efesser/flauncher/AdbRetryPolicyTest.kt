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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AdbRetryPolicyTest {
    @Test
    fun immediateStreamFailuresExhaustRetriesDespiteSuccessfulHandshakes() {
        val policy = AdbRetryPolicy()
        val delays = (1..12).map { policy.nextDelay(10) }
        assertEquals(listOf(5_000L, 15_000L, 30_000L, 60_000L), delays.take(4))
        assertEquals(List(8) { 120_000L }, delays.drop(4))
        assertNull(policy.nextDelay(10))
    }

    @Test
    fun anIdleButStableStreamRestoresReconnectBudget() {
        val policy = AdbRetryPolicy()
        repeat(12) { policy.nextDelay(0) }
        assertEquals(5_000L, policy.nextDelay(30_000))
        assertEquals(15_000L, policy.nextDelay(0))
    }

    @Test
    fun manualConnectRestoresBudget() {
        val policy = AdbRetryPolicy()
        repeat(12) { policy.nextDelay(0) }
        assertNull(policy.nextDelay(29_999))
        policy.reset()
        assertEquals(5_000L, policy.nextDelay(0))
    }
}
