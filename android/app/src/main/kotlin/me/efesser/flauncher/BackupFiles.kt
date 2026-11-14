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

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.IOException

/**
 * Backup files in the shared Downloads folder and in documents the user
 * picks. Everything here does file I/O, so callers run it off the UI thread.
 */
internal class BackupFiles(private val context: Context) {
    private val contentResolver: ContentResolver get() = context.contentResolver

    fun saveBackupToDownloads(filePath: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null

        val file = File(filePath).canonicalFile
        val privateDirectory = File(context.applicationInfo.dataDir).canonicalFile
        require(file.path.startsWith(privateDirectory.path + File.separator) && file.isFile) {
            "Backup source must be an app-private file"
        }
        require(file.name.startsWith("flauncher_backup_") && file.name.endsWith(".json")) {
            "Invalid backup filename"
        }
        require(file.length() <= BackupJson.MAX_BYTES) { "Backup exceeds 32 MiB" }

        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IOException("Unable to create backup in Downloads")
        try {
            contentResolver.openOutputStream(uri, "w").use { output ->
                if (output == null) throw IOException("Unable to write backup in Downloads")
                FileInputStream(file).use { input -> input.copyTo(output) }
            }
            val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            if (contentResolver.update(uri, published, null, null) != 1) {
                throw IOException("Unable to publish backup in Downloads")
            }
            val displayName = contentResolver.query(
                uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: file.name
            return "${Environment.DIRECTORY_DOWNLOADS}/$displayName"
        } catch (e: Exception) {
            try {
                contentResolver.delete(uri, null, null)
            } catch (cleanupError: Exception) {
                android.util.Log.w("FLauncher", "Unable to remove incomplete backup", cleanupError)
            }
            throw e
        }
    }

    fun listBackupJsonInDownloads(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        return try {
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

            val projection = arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATE_MODIFIED,
            )

            val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
            val selectionArgs = arrayOf("flauncher_backup_%", "%.json")
            val sortOrder = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"

            contentResolver.query(collection, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val modifiedCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol)
                    val modifiedSeconds = cursor.getLong(modifiedCol)
                    val uri = ContentUris.withAppendedId(collection, id)
                    results.add(
                        mapOf(
                            "uri" to uri.toString(),
                            "name" to name,
                            "modified" to (modifiedSeconds * 1000L),
                        )
                    )
                }
            }

            results
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun readContentUri(uriString: String): String? {
        return try {
            val uri = Uri.parse(uriString)
            contentResolver.openInputStream(uri).use { input ->
                if (input == null) return null
                BackupJson.read(input)
            }
        } catch (_: Exception) {
            null
        }
    }

    /** Reads the document the picker returned; null when it cannot be opened. Throws on a read error. */
    fun readPickedDocument(uri: Uri): String? {
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
            // Ignore if persistable permission isn't granted by the picker/provider
        }

        return contentResolver.openInputStream(uri).use { input ->
            if (input == null) null else BackupJson.read(input)
        }
    }
}
