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
import org.junit.Test

class TvInputCatalogTest {
    private val base = "com.mediatek.tvinput/.%s/HW%d"

    private fun spec(
        service: String,
        hw: Int,
        type: Int,
        label: String?,
        custom: String? = null,
        hidden: Boolean = false,
    ) = TvInputSpec(base.format(service, hw), type, custom, label, hidden)

    // The inputs reported by the target Vestel/MediaTek TV, plus one hidden extra.
    private fun tvInputs() = listOf(
        spec("hdmi.HDMIInputService", 6, 1007, "HDMI 3"),
        spec("tuner.TunerInputService", 7, 0, "TV"),
        spec("vga.VGAInputService", 3, 1005, "VGA"),
        spec("hdmi.HDMIInputService", 4, 1007, "HDMI 1"),
        spec("tuner.TunerInputService", 0, 0, "TV"),
        spec("component.ComponentInputService", 2, 1004, "YPbPr"),
        spec("hdmi.HDMIInputService", 5, 1007, "HDMI 2"),
        spec("composite.CompositeInputService", 1, 1001, "AV"),
        spec("scart.ScartInputService", 8, 1003, "SCART", hidden = true),
    )

    @Test
    fun hdmiGroupHoldsOnlyTheThreeHdmiInputs() {
        val hdmi = TvInputCatalog.classify(tvInputs()).hdmi
        assertEquals(listOf("HDMI 1", "HDMI 2", "HDMI 3"), hdmi.map { it.name })
        assertEquals(setOf("hdmi"), hdmi.map { it.group }.toSet())
        assertEquals(setOf(1007), hdmi.map { it.type }.toSet())
    }

    @Test
    fun otherGroupIsOneTunerThenAvYpbprVgaWithHiddenDropped() {
        val other = TvInputCatalog.classify(tvInputs()).other
        assertEquals(listOf("TV", "AV", "YPbPr", "VGA"), other.map { it.name })
        assertEquals("com.mediatek.tvinput/.tuner.TunerInputService/HW0", other[0].id)
        assertEquals(setOf("other"), other.map { it.group }.toSet())
    }

    @Test
    fun duplicateNonTunerInputsWithTheSameLabelCollapse() {
        val other = TvInputCatalog.classify(
            listOf(
                spec("composite.CompositeInputService", 1, 1001, "AV"),
                spec("composite.CompositeInputService", 9, 1001, "AV"),
            )
        ).other
        assertEquals(listOf("com.mediatek.tvinput/.composite.CompositeInputService/HW1"), other.map { it.id })
    }

    @Test
    fun blankLabelsFallBackByType() {
        val other = TvInputCatalog.classify(
            listOf(
                spec("a", 0, 0, null),
                spec("a", 1, 1001, "  "),
                spec("a", 2, 1002, ""),
                spec("a", 3, 1003, null),
                spec("a", 4, 1004, null),
                spec("a", 5, 1005, null),
                spec("a", 6, 1006, null),
                spec("a", 7, 1008, null),
                spec("a", 8, 1000, null),
            )
        ).other
        assertEquals(
            listOf("TV", "AV", "S-Video", "SCART", "YPbPr", "VGA", "DVI", "DisplayPort", "Input"),
            other.map { it.name },
        )
    }

    @Test
    fun customLabelBeatsTheSystemLabelButBlankCustomLabelDoesNot() {
        val other = TvInputCatalog.classify(
            listOf(
                spec("composite.CompositeInputService", 1, 1001, "AV", custom = "Game console"),
                spec("vga.VGAInputService", 3, 1005, "VGA", custom = " "),
            )
        ).other
        assertEquals(listOf("Game console", "VGA"), other.map { it.name })
    }

    @Test
    fun noOtherInputsMeansEmptyOtherGroup() {
        val groups = TvInputCatalog.classify(listOf(spec("hdmi.HDMIInputService", 4, 1007, "HDMI 1")))
        assertEquals(1, groups.hdmi.size)
        assertEquals(emptyList<TvInputEntry>(), groups.other)
    }

    private fun portOf(input: TvInputSpec, all: List<TvInputSpec>) = TvInputCatalog.hdmiPort(input, all)

    private fun hdmi(hw: Int, label: String?, custom: String? = null) =
        spec("hdmi.HDMIInputService", hw, 1007, label, custom)

    @Test
    fun theTargetTvsHdmiInputsKeepPortsOneToThree() {
        val all = tvInputs()
        assertEquals(1, portOf(all.first { it.id.endsWith("HW4") }, all))
        assertEquals(2, portOf(all.first { it.id.endsWith("HW5") }, all))
        assertEquals(3, portOf(all.first { it.id.endsWith("HW6") }, all))
    }

    @Test
    fun aDigitInsideAnotherNameIsNotAPort() {
        val all = listOf(hdmi(4, "HDMI 1"), hdmi(5, "HDMI 2"), hdmi(6, "PS4"))
        assertEquals(3, portOf(all[2], all))
    }

    @Test
    fun hdmiWithASpaceGivesThatPort() {
        val all = listOf(hdmi(4, "HDMI 2"), hdmi(5, null))
        assertEquals(2, portOf(all[0], all))
    }

    @Test
    fun hdmiWithoutASpaceAndASuffixGivesThatPort() {
        val all = listOf(hdmi(4, "HDMI2 (ARC)"), hdmi(5, null))
        assertEquals(2, portOf(all[0], all))
    }

    @Test
    fun theHdmiWordIsMatchedIgnoringCase() {
        val all = listOf(hdmi(4, "hdmi 3"))
        assertEquals(3, portOf(all[0], all))
    }

    @Test
    fun unlabeledInputsTakeTheirPositionAmongHdmiInputsSortedById() {
        // Listed out of order, with a tuner and a VGA input that do not count.
        val all = listOf(
            hdmi(6, null),
            spec("tuner.TunerInputService", 0, 0, "TV"),
            hdmi(4, ""),
            spec("vga.VGAInputService", 3, 1005, "VGA"),
            hdmi(5, "Game console"),
        )
        assertEquals(1, portOf(all[2], all))
        assertEquals(2, portOf(all[4], all))
        assertEquals(3, portOf(all[0], all))
    }

    @Test
    fun aCustomLabelDoesNotSetThePort() {
        val all = listOf(hdmi(4, null, custom = "HDMI 3"), hdmi(5, null))
        assertEquals(1, portOf(all[0], all))
    }

    @Test
    fun anInputMissingFromTheListIsPortOne() {
        assertEquals(1, portOf(hdmi(9, null), listOf(hdmi(4, null))))
    }

    @Test
    fun mediaTekSourceValuesFollowThePort() {
        assertEquals(23, TvInputCatalog.mediaTekSource(1))
        assertEquals(25, TvInputCatalog.mediaTekSource(2))
        assertEquals(24, TvInputCatalog.mediaTekSource(3))
        assertEquals(26, TvInputCatalog.mediaTekSource(4))
        assertEquals(23, TvInputCatalog.mediaTekSource(5))
    }
}
