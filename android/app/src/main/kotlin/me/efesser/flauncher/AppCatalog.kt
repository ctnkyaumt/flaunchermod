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

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.Serializable

/**
 * The installed apps as the launcher shows them, with icons and banners
 * encoded as PNG. Slow (icon encoding), so callers run it off the UI thread;
 * the package manager may be used from any thread.
 */
internal class AppCatalog(private val context: Context) {
    private val packageManager: PackageManager get() = context.packageManager

    fun getApplications(): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
        val nonTvActivitiesInfo = queryIntentActivities(true)
                .filter { nonTvActivityInfo -> !tvActivitiesInfo.any { tvActivityInfo -> tvActivityInfo.packageName == nonTvActivityInfo.packageName } }
        return tvActivitiesInfo.mapNotNull { buildAppMapOrNull(it, false) } +
            nonTvActivitiesInfo.mapNotNull { buildAppMapOrNull(it, true) }
    }

    fun getApplication(packageName: String): Map<String, Serializable?>? {
        return packageManager.getLeanbackLaunchIntentForPackage(packageName)
            ?.resolveActivityInfo(packageManager, 0)
            ?.let { buildAppMapOrNull(it, false) }
            ?: return packageManager.getLaunchIntentForPackage(packageName)
                ?.resolveActivityInfo(packageManager, 0)
                ?.let { buildAppMapOrNull(it, true) }
    }

    /** Null when the package was removed between being listed and looked up. */
    private fun buildAppMapOrNull(activityInfo: ActivityInfo, sideloaded: Boolean): Map<String, Serializable?>? =
        try {
            buildAppMap(activityInfo, sideloaded)
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }

    /**
     * Every app worth offering as a button mapping target.
     *
     * [getApplications] only returns what resolves a launcher intent, which
     * leaves out disabled apps — and the apps a remote has a dedicated button
     * for are exactly the ones people disable. Ask the package manager for the
     * disabled components too, then keep anything launchable plus anything
     * disabled.
     */
    @Suppress("DEPRECATION")
    fun getMappableApplications(): List<Map<String, Serializable?>> {
        // MATCH_DISABLED_COMPONENTS alone misses the preloads that sit in the
        // DISABLED_UNTIL_USED state, which is how most TV firmware ships the
        // streaming apps people then turn off. Same values under both names;
        // the newer ones only exist from API 24.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PackageManager.MATCH_DISABLED_COMPONENTS or
                PackageManager.MATCH_DISABLED_UNTIL_USED_COMPONENTS
        } else {
            PackageManager.GET_DISABLED_COMPONENTS
        }
        val self = context.packageName
        val byPackage = LinkedHashMap<String, Map<String, Serializable?>>()

        // Launchable apps first, from the same cheap query the launcher already
        // uses. This part must not depend on the bulk call below, which returns
        // every package on the device and can blow the binder transaction limit
        // on a TV with a large system image.
        for (activityInfo in queryIntentActivities(false) + queryIntentActivities(true)) {
            if (activityInfo.packageName == self) continue
            byPackage.getOrPut(activityInfo.packageName) {
                mapOf(
                    "name" to activityInfo.loadLabel(packageManager).toString(),
                    "packageName" to activityInfo.packageName,
                    "enabled" to true,
                )
            }
        }

        // Then the disabled ones, which resolve no launcher intent and so are
        // invisible above. Best effort: if this fails the list is still usable.
        try {
            for (info in packageManager.getInstalledApplications(flags)) {
                if (info.packageName == self || byPackage.containsKey(info.packageName)) continue
                if (!isDisabled(info)) continue
                byPackage[info.packageName] = mapOf(
                    "name" to runCatching { info.loadLabel(packageManager).toString() }
                        .getOrDefault(info.packageName),
                    "packageName" to info.packageName,
                    "enabled" to false,
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("FLauncher", "Could not list disabled applications", e)
        }

        return byPackage.values.sortedBy { (it["name"] as String).lowercase() }
    }

    /**
     * Whether the user has switched this app off.
     *
     * [ApplicationInfo.enabled] misses `DISABLED_UNTIL_USED`, the state most TV
     * preloads sit in, so ask for the enabled setting as well.
     */
    private fun isDisabled(info: ApplicationInfo): Boolean {
        if (!info.enabled) return true
        val setting = try {
            packageManager.getApplicationEnabledSetting(info.packageName)
        } catch (e: IllegalArgumentException) {
            return false
        }
        return setting == PackageManager.COMPONENT_ENABLED_STATE_DISABLED ||
            setting == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER ||
            setting == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED
    }

    fun applicationExists(packageName: String) = try {
        packageManager.getApplicationInfo(packageName, 0)
        val intent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
            ?: packageManager.getLaunchIntentForPackage(packageName)
        intent != null
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun queryIntentActivities(sideloaded: Boolean) = packageManager
            .queryIntentActivities(Intent(Intent.ACTION_MAIN, null)
                    .addCategory(if (sideloaded) Intent.CATEGORY_LAUNCHER else Intent.CATEGORY_LEANBACK_LAUNCHER), 0)
            .map(ResolveInfo::activityInfo)

    private fun buildAppMap(activityInfo: ActivityInfo, sideloaded: Boolean): Map<String, Serializable?> {
        val packageInfo = packageManager.getPackageInfo(activityInfo.packageName, 0)
        val isSystemApp = (packageInfo.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
        return mapOf(
            "name" to activityInfo.loadLabel(packageManager).toString(),
            "packageName" to activityInfo.packageName,
            "banner" to activityInfo.loadBanner(packageManager)?.let(::drawableToByteArray),
            "icon" to activityInfo.loadIcon(packageManager)?.let(::drawableToByteArray),
            "version" to packageInfo.versionName,
            "sideloaded" to sideloaded,
            "isSystemApp" to isSystemApp,
        )
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray? {
        if (drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) {
            return null
        }

        fun drawableToBitmap(drawable: Drawable): Bitmap {
            val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

        val bitmap = drawableToBitmap(drawable)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
