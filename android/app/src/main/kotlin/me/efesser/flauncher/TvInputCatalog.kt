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

    private val hdmiPortLabel = Regex("""^\s*HDMI ?(\d+)\b""", RegexOption.IGNORE_CASE)

    /**
     * The HDMI port number of [input], 1-based.
     *
     * Android's public API does not expose the port, so it is read only from a
     * system label of the strict form "HDMI <n>" ("HDMI 2", "HDMI2 (ARC)").
     * Any other label ("PS4", a custom name) is ignored and the port is the
     * input's position among all of the device's HDMI inputs sorted by id,
     * hidden ones included since they still occupy a port.
     */
    fun hdmiPort(input: TvInputSpec, all: List<TvInputSpec>): Int {
        input.label
            ?.let { hdmiPortLabel.find(it) }
            ?.groupValues?.get(1)
            ?.toIntOrNull()
            ?.takeIf { it > 0 }
            ?.let { return it }
        val position = all.filter { it.type == TYPE_HDMI }
            .map { it.id }
            .distinct()
            .sorted()
            .indexOf(input.id)
        return if (position >= 0) position + 1 else 1
    }

    /** The MediaTek input source value for an HDMI [port] (found by testing; 4 assumed). */
    fun mediaTekSource(port: Int): Int = when (port) {
        1 -> 23 // HDMI1
        2 -> 25 // HDMI2
        3 -> 24 // HDMI3
        4 -> 26 // HDMI4 (assumed)
        else -> 23 // Default to HDMI1
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
