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

class NodeOpenRetryPolicyTest {
    @Test
    fun delaysGrowFromAHundredMillisecondsToTwoSeconds() {
        val policy = NodeOpenRetryPolicy()
        val delays = (1..5).map { policy.nextDelay() }
        assertEquals(listOf(100L, 250L, 500L, 1_000L, 2_000L), delays)
    }

    @Test
    fun givesUpAfterFiveRetriesAndStaysGivenUp() {
        val policy = NodeOpenRetryPolicy()
        repeat(5) { policy.nextDelay() }
        assertNull(policy.nextDelay())
        assertNull(policy.nextDelay())
    }

    @Test
    fun eachNodeStartsItsOwnBudget() {
        val first = NodeOpenRetryPolicy()
        repeat(5) { first.nextDelay() }
        assertNull(first.nextDelay())
        assertEquals(100L, NodeOpenRetryPolicy().nextDelay())
    }

    @Test
    fun totalWaitIsBoundedToUnderFourSeconds() {
        val policy = NodeOpenRetryPolicy()
        var total = 0L
        while (true) total += policy.nextDelay() ?: break
        assertEquals(3_850L, total)
    }
}
