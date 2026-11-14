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

import java.io.ByteArrayInputStream
import java.io.IOException
import java.nio.charset.CharacterCodingException
import org.junit.Assert.assertEquals
import org.junit.Test

class BackupJsonTest {
    private fun stream(bytes: ByteArray) = ByteArrayInputStream(bytes)

    @Test
    fun readsUtf8Text() {
        val text = "{\"name\":\"Çay ☕\"}"
        assertEquals(text, BackupJson.read(stream(text.toByteArray(Charsets.UTF_8))))
    }

    @Test
    fun readsTextLongerThanOneBuffer() {
        val text = "a".repeat(20_000)
        assertEquals(text, BackupJson.read(stream(text.toByteArray(Charsets.UTF_8))))
    }

    @Test
    fun aBackupOfExactlyTheLimitIsRead() {
        assertEquals("0123456789", BackupJson.read(stream("0123456789".toByteArray()), maxBytes = 10))
    }

    @Test(expected = IOException::class)
    fun aBackupOverTheLimitIsRefused() {
        BackupJson.read(stream("0123456789X".toByteArray()), maxBytes = 10)
    }

    @Test(expected = CharacterCodingException::class)
    fun invalidUtf8IsRefused() {
        BackupJson.read(stream(byteArrayOf(0xC3.toByte(), 0x28)))
    }

    @Test
    fun theDefaultLimitIs32MiB() {
        assertEquals(32 * 1024 * 1024, BackupJson.MAX_BYTES)
    }
}
