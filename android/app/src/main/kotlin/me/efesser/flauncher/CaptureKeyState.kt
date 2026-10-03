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

/** Keeps capture filtering consistent when a dialog opens between a key's edges. */
internal class CaptureKeyState {
    enum class Decision { CAPTURE, CONSUME, PASS_THROUGH }

    private val keysDown = mutableSetOf<String>()

    fun onKey(identity: String, action: Int, repeatCount: Int, capturing: Boolean): Decision {
        if (action == ACTION_UP) {
            // A DOWN that reached Android must also release Android's repeat state.
            if (!keysDown.remove(identity)) return Decision.PASS_THROUGH
            return if (capturing) Decision.CAPTURE else Decision.CONSUME
        }
        if (capturing) {
            if (action == ACTION_DOWN) ownDown(identity, repeatCount)
            return Decision.CAPTURE
        }
        if (action == ACTION_DOWN) {
            if (repeatCount > 0 && identity in keysDown) return Decision.CONSUME
            keysDown.remove(identity)
        }
        return Decision.PASS_THROUGH
    }

    fun ownDown(identity: String, repeatCount: Int) {
        // A repeat may belong to the OK press that opened capture.
        if (repeatCount == 0) keysDown.add(identity)
    }

    private companion object {
        const val ACTION_DOWN = 0
        const val ACTION_UP = 1
    }
}
