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

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EnabledAccessibilityServicesTest {
    private val packageName = "me.efesser.flauncher"
    private val className = "me.efesser.flauncher.FLauncherAccessibilityService"

    private fun enabled(setting: String?) = EnabledAccessibilityServices.contains(setting, packageName, className)

    @Test
    fun aServiceEnabledWithTheShortClassNameIsEnabled() {
        assertTrue(enabled("me.efesser.flauncher/.FLauncherAccessibilityService"))
    }

    @Test
    fun aServiceWrittenInFullAmongOthersIsEnabled() {
        assertTrue(
            enabled(
                "com.other.app/com.other.app.Service:" +
                    "me.efesser.flauncher/me.efesser.flauncher.FLauncherAccessibilityService"
            )
        )
    }

    @Test
    fun anotherAppsServiceOrAnEmptySettingIsNotEnabled() {
        assertFalse(enabled("com.other.app/me.efesser.flauncher.FLauncherAccessibilityService"))
        assertFalse(enabled("com.other.app/.FLauncherAccessibilityService"))
        assertFalse(enabled(""))
        assertFalse(enabled(null))
    }
}
