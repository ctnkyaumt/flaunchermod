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

import org.junit.Assert.*
import org.junit.Test

class ButtonMappingStoreTest {
    @Test
    fun vendorButtonsWithSameLinuxCodeRemainDistinct() {
        val mappings = ButtonMappingStore.parse("""{
            "rawMappings": [
                {"code":240,"rawScanCode":786597,"single":{"type":"openFlauncher"}},
                {"code":240,"rawScanCode":786551,"single":{"type":"openSettings"}}
            ]
        }""")
        assertEquals(2, mappings.rawBindings.size)
        assertEquals(ButtonMappingStore.Action.OpenFlauncher, mappings.resolveRaw(240, 0xc00a5)?.single)
        assertEquals(ButtonMappingStore.Action.OpenSettings, mappings.resolveRaw(240, 0xc0077)?.single)
        assertNull(mappings.resolveRaw(240, 0xc00b6))
        assertNull(mappings.resolveRaw(240, 0))
    }

    @Test
    fun legacyRawBindingsStillWorkAndSpecificUsageWins() {
        val mappings = ButtonMappingStore.parse("""{
            "rawMappings": [
                {"code":240,"single":{"type":"openSettings"}},
                {"code":240,"rawScanCode":786597,"single":{"type":"openFlauncher"}}
            ]
        }""")
        assertEquals(ButtonMappingStore.Action.OpenFlauncher, mappings.resolveRaw(240, 0xc00a5)?.single)
        assertEquals(ButtonMappingStore.Action.OpenSettings, mappings.resolveRaw(240, 0xc0077)?.single)
        assertEquals(ButtonMappingStore.Action.OpenSettings, mappings.resolveRaw(240, 0)?.single)
    }

    @Test
    fun androidScanAndLinuxUsageNamespacesAreSeparate() {
        val mappings = ButtonMappingStore.parse("""{
            "keyMappings": [
                {"keyCode":0,"scanCode":240,"matchMode":"scanCode","single":{"type":"block"}}
            ],
            "rawMappings": [
                {"code":240,"rawScanCode":786597,"single":{"type":"openFlauncher"}}
            ]
        }""")
        assertEquals(ButtonMappingStore.Action.Block, mappings.resolve(0, 240)?.single)
        assertEquals(ButtonMappingStore.Action.OpenFlauncher, mappings.resolveRaw(240, 0xc00a5)?.single)
    }
}
