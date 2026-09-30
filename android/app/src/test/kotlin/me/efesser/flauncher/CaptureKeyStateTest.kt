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
