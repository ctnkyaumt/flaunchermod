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
import java.io.File

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

    // The samples below are shared with test/providers/button_mapping_format_test.dart,
    // which decodes the same files with the Dart reader.

    /**
     * Reads test/fixtures/button_mappings/[name], searching upwards from the
     * working directory (android/app under Gradle) so the module directory does
     * not matter.
     */
    private fun sample(name: String): String {
        val relative = File("test/fixtures/button_mappings/$name")
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, relative.path)
            if (candidate.isFile) return candidate.readText(Charsets.UTF_8)
            dir = dir.parentFile
        }
        throw AssertionError(
            "Shared sample ${relative.path} not found above ${File("").absolutePath}",
        )
    }

    private fun parseSample(name: String) = ButtonMappingStore.parse(sample(name))

    @Test
    fun sampleEmptyHasNothing() {
        val mappings = parseSample("empty.json")
        assertTrue(mappings.bindings.isEmpty())
        assertTrue(mappings.appRedirects.isEmpty())
        assertTrue(mappings.rawBindings.isEmpty())
    }

    @Test
    fun sampleAndroidKeysResolveByKeyCodeAndByScanCode() {
        val mappings = parseSample("android_keys.json")
        assertEquals(3, mappings.bindings.size)

        val guide = mappings.resolve(172, 0)
        assertEquals(ButtonMappingStore.MatchMode.KEY_CODE, guide?.matchMode)
        assertEquals(ButtonMappingStore.Action.LaunchApp("com.netflix.ninja"), guide?.single)
        assertEquals(ButtonMappingStore.Action.OpenFlauncher, guide?.long)
        assertNull(guide?.double)
        assertEquals(guide, mappings.resolve(172, 999))

        val unknown = mappings.resolve(0, 295)
        assertEquals(ButtonMappingStore.MatchMode.SCAN_CODE, unknown?.matchMode)
        assertEquals(295, unknown?.scanCode)
        assertEquals(ButtonMappingStore.Action.OpenSettings, unknown?.double)
        assertNull(unknown?.single)

        // An explicit scan-code binding wins over the key-code one.
        assertEquals(ButtonMappingStore.Action.Block, mappings.resolve(172, 314)?.single)
        assertNull(mappings.resolve(23, 0))
    }

    @Test
    fun sampleRawKeysResolveByLinuxCodeAndUsage() {
        val mappings = parseSample("raw_keys.json")
        assertEquals(4, mappings.rawBindings.size)
        assertEquals(ButtonMappingStore.Action.OpenFlauncher, mappings.resolveRaw(240, 786597)?.single)
        val settings = mappings.resolveRaw(240, 786551)
        assertEquals(ButtonMappingStore.Action.OpenSettings, settings?.single)
        assertEquals(ButtonMappingStore.Action.Block, settings?.long)
        assertNull(mappings.resolveRaw(240, 1))
        assertEquals(
            ButtonMappingStore.Action.LaunchApp("com.spotify.tv.android"),
            mappings.resolveRaw(116, 0)?.double,
        )
        assertEquals(ButtonMappingStore.Action.Block, mappings.resolveRaw(142, 5)?.single)
    }

    @Test
    fun sampleAppRedirectsMapSourcePackageToAction() {
        val mappings = parseSample("app_redirects.json")
        assertEquals(
            mapOf(
                "com.netflix.ninja" to ButtonMappingStore.Action.LaunchApp("com.plexapp.android"),
                "com.google.android.youtube.tv" to ButtonMappingStore.Action.OpenFlauncher,
            ),
            mappings.appRedirects,
        )
    }

    @Test
    fun sampleLegacyKeyMappingsKeepTheirOldMeaning() {
        val mappings = parseSample("legacy_key_mappings.json")
        assertEquals(
            listOf(
                ButtonMappingStore.MatchMode.KEY_CODE,
                ButtonMappingStore.MatchMode.SCAN_CODE,
                ButtonMappingStore.MatchMode.KEY_CODE,
            ),
            mappings.bindings.map { it.matchMode },
        )
        assertEquals(ButtonMappingStore.Action.OpenSettings, mappings.resolve(172, 0)?.single)
        assertEquals(ButtonMappingStore.Action.Block, mappings.resolve(0, 314)?.long)
        assertEquals(ButtonMappingStore.Action.OpenFlauncher, mappings.resolve(23, 0)?.single)
    }

    @Test
    fun sampleLegacyRawMappingsWithoutUsageMatchAnyUsage() {
        val mappings = parseSample("legacy_raw_mappings.json")
        assertEquals(2, mappings.rawBindings.size)
        assertEquals(ButtonMappingStore.Action.OpenSettings, mappings.resolveRaw(240, 0)?.single)
        assertEquals(ButtonMappingStore.Action.OpenSettings, mappings.resolveRaw(240, 786597)?.single)
        assertEquals(ButtonMappingStore.Action.OpenFlauncher, mappings.resolveRaw(116, 0)?.long)
    }

    @Test
    fun sampleLegacyAppRedirectsWithoutOtherListsStillLoad() {
        val mappings = parseSample("legacy_app_redirects.json")
        assertTrue(mappings.bindings.isEmpty())
        assertTrue(mappings.rawBindings.isEmpty())
        assertEquals(
            mapOf("com.netflix.ninja" to ButtonMappingStore.Action.LaunchApp("com.plexapp.android")),
            mappings.appRedirects,
        )
    }

    @Test
    fun sampleDroppedEntriesAreSkippedLikeTheDartReaderSkipsThem() {
        val mappings = parseSample("dropped_entries.json")
        assertEquals(1, mappings.bindings.size)
        assertEquals(19, mappings.bindings[0].keyCode)
        assertEquals(ButtonMappingStore.Action.OpenSettings, mappings.bindings[0].single)
        assertEquals(
            mapOf("com.example.ok" to ButtonMappingStore.Action.Block),
            mappings.appRedirects,
        )
        assertEquals(setOf(ButtonMappingStore.RawKey(97)), mappings.rawBindings.keys)
    }

    @Test
    fun unknownKeyCodeWithoutMatchModeAndScanCodeIsDropped() {
        // Dart treats a missing matchMode on keyCode 0 as scan-code mode and
        // then rejects the entry for lacking a scan code.
        val mappings = ButtonMappingStore.parse("""{
            "keyMappings": [
                {"keyCode":0,"single":{"type":"block"}},
                {"keyCode":0,"scanCode":50,"matchMode":"bogus","single":{"type":"block"}}
            ]
        }""")
        assertEquals(1, mappings.bindings.size)
        assertEquals(ButtonMappingStore.MatchMode.KEY_CODE, mappings.bindings[0].matchMode)
        assertNull(mappings.resolve(5, 0))
    }
}
