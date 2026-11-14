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

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ApkInstallRulesTest {
    @get:Rule
    val temp = TemporaryFolder()

    private fun cacheDir(): File = temp.newFolder("cache")

    private fun installable(cacheDir: File, relative: String) =
        ApkInstallRules.isInApkDownloads(cacheDir, File(cacheDir, relative))

    @Test
    fun anApkInTheDownloadFolderIsAccepted() {
        assertTrue(installable(cacheDir(), "apk_downloads/app.apk"))
    }

    @Test
    fun anApkInASubfolderOfTheDownloadFolderIsAccepted() {
        assertTrue(installable(cacheDir(), "apk_downloads/42/app.apk"))
    }

    @Test
    fun anApkElsewhereInTheCacheIsRefused() {
        assertFalse(installable(cacheDir(), "app.apk"))
    }

    @Test
    fun aPathThatClimbsOutOfTheDownloadFolderIsRefused() {
        assertFalse(installable(cacheDir(), "apk_downloads/../app.apk"))
    }

    @Test
    fun aSiblingFolderSharingTheNamePrefixIsRefused() {
        assertFalse(installable(cacheDir(), "apk_downloads_old/app.apk"))
    }

    @Test
    fun theDownloadFolderItselfIsRefused() {
        assertFalse(installable(cacheDir(), "apk_downloads"))
    }

    @Test
    fun theAppFilesFolderIsRefused() {
        val cache = cacheDir()
        val privateKey = File(temp.root, "app_flutter/adb_private.key")
        assertFalse(ApkInstallRules.isInApkDownloads(cache, privateKey))
    }

    @Test
    fun pendingUserActionAsksTheUser() {
        // PackageInstaller.STATUS_PENDING_USER_ACTION
        assertEquals(SilentInstallNext.ASK_USER, ApkInstallRules.afterSilentStatus(-1))
    }

    @Test
    fun successNeedsNothingMore() {
        // PackageInstaller.STATUS_SUCCESS
        assertEquals(SilentInstallNext.DONE, ApkInstallRules.afterSilentStatus(0))
    }

    @Test
    fun everyFailureFallsBackToTheNormalInstaller() {
        // STATUS_FAILURE .. STATUS_FAILURE_INCOMPATIBLE, then an unknown value.
        for (status in listOf(1, 2, 3, 4, 5, 6, 7, 99)) {
            assertEquals("status $status", SilentInstallNext.FALL_BACK, ApkInstallRules.afterSilentStatus(status))
        }
    }
}
