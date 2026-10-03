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

import me.efesser.flauncher.CaptureKeyState.Decision.CAPTURE
import me.efesser.flauncher.CaptureKeyState.Decision.CONSUME
import me.efesser.flauncher.CaptureKeyState.Decision.PASS_THROUGH
import org.junit.Assert.assertEquals
import org.junit.Test

class CaptureKeyStateTest {
    private val ok = "android:7:23:353"
    private val netflix = "android:1:265:104"

    @Test
    fun openingDownBeforeCaptureStillReleasesAndroidInsideCapture() {
        val state = CaptureKeyState()
        assertEquals(PASS_THROUGH, state.onKey(ok, 0, 0, capturing = false))
        assertEquals(PASS_THROUGH, state.onKey(ok, 1, 0, capturing = true))
    }

    @Test
    fun capturedPressOwnsItsUpAfterDisarming() {
        val state = CaptureKeyState()
        assertEquals(CAPTURE, state.onKey(netflix, 0, 0, capturing = true))
        assertEquals(CONSUME, state.onKey(netflix, 1, 0, capturing = false))
        assertEquals(PASS_THROUGH, state.onKey(netflix, 0, 0, capturing = false))
        assertEquals(PASS_THROUGH, state.onKey(netflix, 1, 0, capturing = false))
    }

    @Test
    fun openingRepeatsCannotClaimItsRelease() {
        val state = CaptureKeyState()
        assertEquals(PASS_THROUGH, state.onKey(ok, 0, 0, capturing = false))
        assertEquals(CAPTURE, state.onKey(ok, 0, 1, capturing = true))
        assertEquals(CAPTURE, state.onKey(ok, 0, 2, capturing = true))
        assertEquals(PASS_THROUGH, state.onKey(ok, 1, 0, capturing = true))
    }

    @Test
    fun heldCapturedPressKeepsRepeatsConsumedUntilItsRelease() {
        val state = CaptureKeyState()
        assertEquals(CAPTURE, state.onKey(netflix, 0, 0, capturing = true))
        assertEquals(CAPTURE, state.onKey(netflix, 0, 1, capturing = true))
        assertEquals(CONSUME, state.onKey(netflix, 0, 2, capturing = false))
        assertEquals(CONSUME, state.onKey(netflix, 1, 0, capturing = false))
        assertEquals(PASS_THROUGH, state.onKey(netflix, 0, 3, capturing = false))
    }

    @Test
    fun unrelatedOpeningReleaseDoesNotClearAnOwnedPress() {
        val state = CaptureKeyState()
        assertEquals(CAPTURE, state.onKey(netflix, 0, 0, capturing = true))
        assertEquals(PASS_THROUGH, state.onKey(ok, 1, 0, capturing = true))
        assertEquals(CAPTURE, state.onKey(netflix, 1, 0, capturing = true))
        assertEquals(PASS_THROUGH, state.onKey(netflix, 1, 0, capturing = true))
    }
}
