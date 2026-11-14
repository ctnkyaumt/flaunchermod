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

import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream

/** What [ApkInstaller.prepare] decided; [ApkInstaller.finish] carries it out on the UI thread. */
internal sealed class InstallStep {
    /** Nothing left to start; answer with [result]. */
    class Done(val result: String) : InstallStep()

    /** Open the "install unknown apps" setting, answer "needs_permission". */
    object AskPermission : InstallStep()

    /** Hand [file] to the system installer. */
    class OpenInstaller(val file: File) : InstallStep()
}

/**
 * Installs downloaded APKs, only from `<cacheDir>/apk_downloads/`.
 *
 * [prepare] does the slow part (checks, the device-owner session copy) and
 * runs in the background; [finish] starts activities and runs on the UI thread.
 * Results are the strings the Dart side already knows: "file_missing",
 * "silent_started", "missing_manifest_permission", "needs_permission",
 * "started", "error".
 */
internal class ApkInstaller(private val context: Context) {
    private val statusReceivers = HashMap<Int, BroadcastReceiver>()

    fun prepare(filePath: String): InstallStep {
        val file = File(filePath)
        if (!file.exists()) return InstallStep.Done("file_missing")
        if (!ApkInstallRules.isInApkDownloads(context.cacheDir, file)) {
            android.util.Log.e("FLauncher", "Refusing to install an APK outside ${ApkInstallRules.DOWNLOAD_DIRECTORY}")
            return InstallStep.Done("error")
        }

        if (isDeviceOwnerApp() && startSilentInstall(file)) {
            return InstallStep.Done("silent_started")
        }

        return checkPermission(file)
    }

    fun finish(step: InstallStep): String = when (step) {
        is InstallStep.Done -> step.result
        is InstallStep.AskPermission -> {
            openUnknownSourcesSettings()
            "needs_permission"
        }
        is InstallStep.OpenInstaller -> openInstaller(step.file)
    }

    fun canRequestPackageInstalls(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return context.packageManager.canRequestPackageInstalls()
        }
        return true
    }

    fun requestPackageInstallsPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (e: Exception) {
                android.util.Log.e("FLauncher", "Error opening unknown sources settings: ${e.message}")
                return false
            }
        }
        return true
    }

    /** Drops the receivers of silent installs still waiting for a status. */
    fun release() {
        val receivers = synchronized(statusReceivers) {
            val all = statusReceivers.values.toList()
            statusReceivers.clear()
            all
        }
        receivers.forEach(::unregister)
    }

    private fun checkPermission(file: File): InstallStep {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canInstall = try {
                context.packageManager.canRequestPackageInstalls()
            } catch (e: SecurityException) {
                android.util.Log.e("FLauncher", "Missing REQUEST_INSTALL_PACKAGES in manifest: ${e.message}")
                return InstallStep.Done("missing_manifest_permission")
            }
            if (!canInstall) return InstallStep.AskPermission
        }
        return InstallStep.OpenInstaller(file)
    }

    private fun openUnknownSourcesSettings() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e("FLauncher", "Error opening unknown sources settings: ${e.message}")
        }
    }

    private fun openInstaller(file: File): String = try {
        val uri = FileProvider.getUriForFile(
            context,
            context.applicationContext.packageName + ".fileprovider",
            file
        )

        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE)
        intent.data = uri
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        intent.putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
        context.startActivity(intent)
        "started"
    } catch (e: Exception) {
        android.util.Log.e("FLauncher", "Error installing APK: ${e.message}")
        e.printStackTrace()
        "error"
    }

    private fun isDeviceOwnerApp(): Boolean {
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.isDeviceOwnerApp(context.packageName)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Installs [file] without asking, which only a device owner may do.
     *
     * False when the session could not be set up or committed; it is then
     * abandoned and the caller uses the normal installer. Once committed, the
     * status receiver takes over: a failure opens the normal installer for
     * this file, a confirmation request is shown to the user.
     */
    private fun startSilentInstall(file: File): Boolean {
        var packageInstaller: PackageInstaller? = null
        var sessionId = -1
        var session: PackageInstaller.Session? = null
        var committed = false
        try {
            val installer = context.packageManager.packageInstaller
            packageInstaller = installer
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            sessionId = installer.createSession(params)
            val openSession = installer.openSession(sessionId)
            session = openSession

            FileInputStream(file).use { input ->
                openSession.openWrite("base.apk", 0, -1).use { output ->
                    val buffer = ByteArray(1024 * 64)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                    openSession.fsync(output)
                }
            }

            val statusSender = registerStatusReceiver(sessionId, file)
            openSession.commit(statusSender)
            committed = true
            return true
        } catch (e: Exception) {
            android.util.Log.w("FLauncher", "Silent install attempt failed: ${e.message}")
            if (sessionId >= 0) dropStatusReceiver(sessionId)
            return false
        } finally {
            if (committed) {
                try {
                    session?.close()
                } catch (e: Exception) {
                    android.util.Log.w("FLauncher", "Closing the install session failed: ${e.message}")
                }
            } else {
                abandon(packageInstaller, sessionId, session)
            }
        }
    }

    private fun abandon(packageInstaller: PackageInstaller?, sessionId: Int, session: PackageInstaller.Session?) {
        if (sessionId < 0) return
        try {
            if (session != null) session.abandon() else packageInstaller?.abandonSession(sessionId)
        } catch (e: Exception) {
            android.util.Log.w("FLauncher", "Abandoning the install session failed: ${e.message}")
        }
    }

    private fun registerStatusReceiver(sessionId: Int, file: File): android.content.IntentSender {
        val action = context.packageName + ACTION_INSTALL_STATUS_SUFFIX
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context?, intent: Intent?) {
                onInstallStatus(sessionId, file, intent)
            }
        }
        synchronized(statusReceivers) { statusReceivers.put(sessionId, receiver) }?.let(::unregister)
        InternalBroadcasts.register(context, receiver, IntentFilter(action))

        // Mutable: the package installer adds the status extras to it.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val intent = Intent(action)
            .setPackage(context.packageName)
            .putExtra(EXTRA_SESSION_ID, sessionId)
        return PendingIntent.getBroadcast(context, sessionId, intent, flags).intentSender
    }

    /** Runs on the UI thread, where registered receivers are called. */
    private fun onInstallStatus(sessionId: Int, file: File, intent: Intent?) {
        if (intent == null || intent.getIntExtra(EXTRA_SESSION_ID, -1) != sessionId) return
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        when (ApkInstallRules.afterSilentStatus(status)) {
            SilentInstallNext.ASK_USER -> {
                // Not final: the real status follows once the user answers.
                @Suppress("DEPRECATION")
                val confirm: Intent? = intent.getParcelableExtra(Intent.EXTRA_INTENT)
                val shown = try {
                    if (confirm != null) {
                        context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        true
                    } else {
                        false
                    }
                } catch (e: Exception) {
                    android.util.Log.w("FLauncher", "Install confirmation unavailable: ${e.message}")
                    false
                }
                if (!shown) {
                    dropStatusReceiver(sessionId)
                    fallBack(file)
                }
            }
            SilentInstallNext.DONE -> dropStatusReceiver(sessionId)
            SilentInstallNext.FALL_BACK -> {
                android.util.Log.w(
                    "FLauncher",
                    "Silent install failed ($status): ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}"
                )
                dropStatusReceiver(sessionId)
                fallBack(file)
            }
        }
    }

    /** The normal installer for [file], as if the silent path had never been tried. */
    private fun fallBack(file: File) {
        finish(checkPermission(file))
    }

    private fun dropStatusReceiver(sessionId: Int) {
        synchronized(statusReceivers) { statusReceivers.remove(sessionId) }?.let(::unregister)
    }

    private fun unregister(receiver: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Already unregistered.
        }
    }

    private companion object {
        const val ACTION_INSTALL_STATUS_SUFFIX = ".action.APK_INSTALL_STATUS"
        const val EXTRA_SESSION_ID = "flauncher.extra.INSTALL_SESSION_ID"
    }
}
