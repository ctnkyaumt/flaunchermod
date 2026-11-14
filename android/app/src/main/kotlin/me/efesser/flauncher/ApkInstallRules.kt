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

/** What to do once the package installer reports on a silent install. */
internal enum class SilentInstallNext { ASK_USER, DONE, FALL_BACK }

/** The install decisions that need no Android API. */
internal object ApkInstallRules {
    /** Under the cache folder; the only folder the file provider shares. */
    const val DOWNLOAD_DIRECTORY = "apk_downloads"

    // Same values as PackageInstaller.STATUS_PENDING_USER_ACTION and STATUS_SUCCESS.
    private const val STATUS_PENDING_USER_ACTION = -1
    private const val STATUS_SUCCESS = 0

    /** Whether [file] sits inside `<cacheDir>/apk_downloads/`, after resolving `..` and links. */
    fun isInApkDownloads(cacheDir: File, file: File): Boolean {
        val directory = File(cacheDir, DOWNLOAD_DIRECTORY).canonicalFile
        return file.canonicalPath.startsWith(directory.path + File.separator)
    }

    fun afterSilentStatus(status: Int): SilentInstallNext = when (status) {
        STATUS_PENDING_USER_ACTION -> SilentInstallNext.ASK_USER
        STATUS_SUCCESS -> SilentInstallNext.DONE
        else -> SilentInstallNext.FALL_BACK
    }
}
