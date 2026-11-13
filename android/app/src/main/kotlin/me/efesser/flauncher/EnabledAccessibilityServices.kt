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

/** Reads the colon-separated `enabled_accessibility_services` setting. */
internal object EnabledAccessibilityServices {
    /**
     * Android accepts a service written in full (`pkg/pkg.Service`) or with
     * the package left off the class (`pkg/.Service`), and a service enabled
     * through `adb shell settings put` is usually written the short way.
     */
    fun contains(setting: String?, packageName: String, className: String): Boolean {
        if (setting.isNullOrEmpty()) return false
        return setting.split(':').any { entry ->
            val separator = entry.indexOf('/')
            if (separator <= 0) return@any false
            val entryPackage = entry.substring(0, separator)
            var entryClass = entry.substring(separator + 1)
            if (entryClass.startsWith(".")) entryClass = entryPackage + entryClass
            entryPackage.equals(packageName, ignoreCase = true) && entryClass.equals(className, ignoreCase = true)
        }
    }
}
