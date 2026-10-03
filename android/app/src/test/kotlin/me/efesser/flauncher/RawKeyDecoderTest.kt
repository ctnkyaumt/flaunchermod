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

class RawKeyDecoderTest {
    @Test
    fun capturedIrReleaseKeepsScanWhenDriverOmitsMsc() {
        val decoder = RawKeyDecoder()
        val keys = listOf(
            "/dev/input/event0: 0004 0004 00000127",
            "/dev/input/event0: 0001 0068 00000001",
            "/dev/input/event0: 0000 0000 00000000",
            "/dev/input/event0: 0001 0068 00000000",
            "/dev/input/event0: 0000 0000 00000000",
        ).mapNotNull(decoder::acceptLine)

        assertEquals(listOf(1, 0), keys.map { it.value })
        assertEquals(listOf(0x127, 0x127), keys.map { it.scanCode })
        assertEquals(listOf(0x68, 0x68), keys.map { it.code })
    }

    @Test
    fun bluetoothVendorButtonsSharingUnknownKeyStayDistinct() {
        val decoder = RawKeyDecoder()
        val keys = listOf(
            "/dev/input/event2: 0004 0004 000c00a5",
            "/dev/input/event2: 0001 00f0 00000001",
            "/dev/input/event2: 0000 0000 00000000",
            "/dev/input/event2: 0004 0004 000c00a5",
            "/dev/input/event2: 0001 00f0 00000000",
            "/dev/input/event2: 0000 0000 00000000",
            "/dev/input/event2: 0004 0004 000c0077",
            "/dev/input/event2: 0001 00f0 00000001",
            "/dev/input/event2: 0000 0000 00000000",
            "/dev/input/event2: 0004 0004 000c0077",
            "/dev/input/event2: 0001 00f0 00000000",
        ).mapNotNull(decoder::acceptLine)

        assertEquals(listOf(240, 240, 240, 240), keys.map { it.code })
        assertEquals(listOf(0xc00a5, 0xc00a5, 0xc0077, 0xc0077), keys.map { it.scanCode })
    }

    @Test
    fun interleavedDevicesDoNotShareFrameOrHeldScans() {
        val decoder = RawKeyDecoder()
        decoder.accept("ir", 4, 4, 0x127)
        decoder.accept("bt", 4, 4, 0xc00a5)
        assertEquals(0x127, decoder.accept("ir", 1, 240, 1)?.scanCode)
        assertEquals(0xc00a5, decoder.accept("bt", 1, 240, 1)?.scanCode)
        decoder.accept("ir", 0, 0, 0)
        decoder.accept("bt", 0, 0, 0)
        assertEquals(0x127, decoder.accept("ir", 1, 240, 0)?.scanCode)
        assertEquals(0xc00a5, decoder.accept("bt", 1, 240, 0)?.scanCode)
    }

    @Test
    fun synReportPreventsScanLeakingIntoNewKey() {
        val decoder = RawKeyDecoder()
        decoder.accept("remote", 4, 4, 0xc00a5)
        decoder.accept("remote", 1, 240, 1)
        decoder.accept("remote", 0, 0, 0)
        assertEquals(0, decoder.accept("remote", 1, 103, 1)?.scanCode)
        // A new down without a usage cannot borrow the previous held usage,
        // even when the firmware reuses KEY_UNKNOWN.
        assertEquals(0, decoder.accept("remote", 1, 240, 1)?.scanCode)
    }

    @Test
    fun usageAppliesOnlyToTheNextKeyEvenWithinOneFrame() {
        val decoder = RawKeyDecoder()
        decoder.accept("remote", 4, 4, 0xc00a5)
        assertEquals(0xc00a5, decoder.accept("remote", 1, 240, 1)?.scanCode)
        assertEquals(0, decoder.accept("remote", 1, 103, 1)?.scanCode)
    }

    @Test
    fun droppedInputClearsUsageAndIgnoresRestOfFrame() {
        val decoder = RawKeyDecoder()
        decoder.accept("remote", 4, 4, 0xc00a5)
        decoder.accept("remote", 1, 240, 1)
        decoder.accept("remote", 0, 0, 0)
        decoder.accept("remote", 0, 3, 0)
        decoder.accept("remote", 4, 4, 0xc0077)
        assertNull(decoder.accept("remote", 1, 240, 1))
        decoder.accept("remote", 0, 0, 0)
        assertEquals(0, decoder.accept("remote", 1, 240, 0)?.scanCode)
    }

    @Test
    fun repeatKeepsHeldScanAndReleaseClearsIt() {
        val decoder = RawKeyDecoder()
        decoder.accept("remote", 4, 4, 0x127)
        decoder.accept("remote", 1, 104, 1)
        decoder.accept("remote", 0, 0, 0)
        assertEquals(0x127, decoder.accept("remote", 1, 104, 2)?.scanCode)
        decoder.accept("remote", 0, 0, 0)
        assertEquals(0x127, decoder.accept("remote", 1, 104, 0)?.scanCode)
        decoder.accept("remote", 0, 0, 0)
        assertEquals(0, decoder.accept("remote", 1, 104, 0)?.scanCode)
    }

    @Test
    fun plainLinuxKeysKeepZeroScan() {
        val decoder = RawKeyDecoder()
        assertEquals(0, decoder.acceptLine("/dev/input/event0: 0001 0067 00000001")?.scanCode)
        assertEquals(0, decoder.acceptLine("/dev/input/event0: 0001 0067 00000000")?.scanCode)
    }

    @Test
    fun unsignedHexScanUsesSameBitsAsBinaryInputEvent() {
        val decoder = RawKeyDecoder()
        decoder.acceptLine("/dev/input/event2: 0004 0004 ffff0001")
        assertEquals(-65535, decoder.acceptLine("/dev/input/event2: 0001 00f0 00000001")?.scanCode)
    }

    @Test
    fun malformedAndNonKeyEventsDoNotEmitKeys() {
        val decoder = RawKeyDecoder()
        listOf(
            "getevent: permission denied",
            "/dev/input/event0: EV_KEY KEY_UNKNOWN DOWN",
            "/dev/input/event0: 0001 00f0 100000000",
            "/dev/input/event0: 0001 00f0 00000003",
            "/dev/input/event0: 0001 00f0 nope",
            "/dev/input/event0: 0003 0000 00000001",
        ).forEach { assertNull(decoder.acceptLine(it)) }
    }
}
