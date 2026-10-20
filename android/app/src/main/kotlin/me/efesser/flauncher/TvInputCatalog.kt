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

/** What Android reports about one TV input, reduced to plain data. */
internal data class TvInputSpec(
    val id: String,
    val type: Int,
    val customLabel: String?,
    val label: String?,
    val hidden: Boolean,
)

/** One input as shown on the Inputs page. [group] is "hdmi" or "other". */
internal data class TvInputEntry(val id: String, val name: String, val type: Int, val group: String)

internal data class TvInputGroups(val hdmi: List<TvInputEntry>, val other: List<TvInputEntry>)

/** Sorts raw TV inputs into the HDMI and Other rows without touching Android APIs. */
internal object TvInputCatalog {
    const val TYPE_TUNER = 0
    const val TYPE_OTHER = 1000
    const val TYPE_COMPOSITE = 1001
    const val TYPE_SVIDEO = 1002
    const val TYPE_SCART = 1003
    const val TYPE_COMPONENT = 1004
    const val TYPE_VGA = 1005
    const val TYPE_DVI = 1006
    const val TYPE_HDMI = 1007
    const val TYPE_DISPLAY_PORT = 1008

    const val GROUP_HDMI = "hdmi"
    const val GROUP_OTHER = "other"

    private val otherTypeOrder = listOf(
        TYPE_TUNER, TYPE_COMPOSITE, TYPE_SVIDEO, TYPE_SCART, TYPE_COMPONENT,
        TYPE_VGA, TYPE_DVI, TYPE_DISPLAY_PORT, TYPE_OTHER,
    )

    fun classify(inputs: List<TvInputSpec>): TvInputGroups {
        val visible = inputs.filter { !it.hidden }.sortedBy { it.id }
        val hdmi = visible.filter { it.type == TYPE_HDMI }.map { entry(it, GROUP_HDMI) }

        val seen = mutableSetOf<Pair<Int, String>>()
        var tunerKept = false
        val other = mutableListOf<TvInputEntry>()
        for (spec in visible.filter { it.type != TYPE_HDMI }.sortedBy { rank(it.type) }) {
            val entry = entry(spec, GROUP_OTHER)
            if (spec.type == TYPE_TUNER) {
                // The TV's own Inputs panel lists a single "TV" however many tuners exist.
                if (tunerKept) continue
                tunerKept = true
            } else if (!seen.add(spec.type to entry.name)) {
                continue
            }
            other.add(entry)
        }
        return TvInputGroups(hdmi, other)
    }

    private fun rank(type: Int): Int {
        val index = otherTypeOrder.indexOf(type)
        return if (index >= 0) index else otherTypeOrder.size
    }

    private fun entry(spec: TvInputSpec, group: String) =
        TvInputEntry(spec.id, labelOf(spec), spec.type, group)

    private fun labelOf(spec: TvInputSpec): String =
        spec.customLabel?.takeIf { it.isNotBlank() }
            ?: spec.label?.takeIf { it.isNotBlank() }
            ?: when (spec.type) {
                TYPE_TUNER -> "TV"
                TYPE_COMPOSITE -> "AV"
                TYPE_SVIDEO -> "S-Video"
                TYPE_SCART -> "SCART"
                TYPE_COMPONENT -> "YPbPr"
                TYPE_VGA -> "VGA"
                TYPE_DVI -> "DVI"
                TYPE_DISPLAY_PORT -> "DisplayPort"
                else -> "Input"
            }
}
