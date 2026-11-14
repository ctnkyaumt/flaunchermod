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

import java.io.IOException
import java.util.Collections
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ChannelWorkTest {
    /** Records every answer, and the thread it arrived on. */
    private class RecordingReply : ChannelReply {
        val calls: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val thread = AtomicReference<Thread>()

        override fun success(value: Any?) {
            thread.set(Thread.currentThread())
            calls.add("success:$value")
        }

        override fun error(code: String, message: String?) {
            thread.set(Thread.currentThread())
            calls.add("error:$code:$message")
        }
    }

    /** Holds tasks until the test runs them, standing in for the UI thread's queue. */
    private class QueuedExecutor : Executor {
        private val tasks = LinkedBlockingQueue<Runnable>()

        override fun execute(command: Runnable) {
            tasks.add(command)
        }

        /** Waits for one task and runs it on the test thread. */
        fun runNext(): Boolean {
            val task = tasks.poll(5, TimeUnit.SECONDS) ?: return false
            task.run()
            return true
        }

        fun runPending() {
            while (true) {
                val task = tasks.poll() ?: return
                task.run()
            }
        }
    }

    private val background: ExecutorService = ChannelWork.newBackgroundExecutor()
    private val ui = QueuedExecutor()
    private val work = ChannelWork(background, ui)

    @After
    fun stop() {
        background.shutdownNow()
    }

    private fun drainBackground() {
        background.shutdown()
        assertTrue(background.awaitTermination(5, TimeUnit.SECONDS))
    }

    @Test
    fun workRunsOffTheCallingThread() {
        val workThread = AtomicReference<Thread>()
        work.call("getApplications", RecordingReply()) {
            workThread.set(Thread.currentThread())
            42
        }

        assertTrue(ui.runNext())
        assertNotNull(workThread.get())
        assertNotSame(Thread.currentThread(), workThread.get())
    }

    @Test
    fun theValueIsDeliveredOnlyThroughTheReplyExecutor() {
        val reply = RecordingReply()
        work.call("getApplications", reply) { "apps" }
        drainBackground()

        assertEquals(emptyList<String>(), reply.calls)
        ui.runPending()
        assertEquals(listOf("success:apps"), reply.calls)
        assertSame(Thread.currentThread(), reply.thread.get())
    }

    @Test
    fun aThrownExceptionBecomesOneNativeErrorReply() {
        val reply = RecordingReply()
        work.call("readContentUri", reply) { throw IOException("disk gone") }

        assertTrue(ui.runNext())
        assertEquals(listOf("error:native_error:disk gone"), reply.calls)
    }

    @Test
    fun theErrorCodeCanBeChosenPerCall() {
        val reply = RecordingReply()
        work.call("pickBackupJson", reply, errorCode = "read_error") { throw IOException("unreadable") }

        assertTrue(ui.runNext())
        assertEquals(listOf("error:read_error:unreadable"), reply.calls)
    }

    @Test
    fun aSuccessfulCallGetsExactlyOneReply() {
        val reply = RecordingReply()
        work.call("listBackupJsonInDownloads", reply) { null }
        drainBackground()
        ui.runPending()

        assertEquals(listOf("success:null"), reply.calls)
    }

    @Test
    fun aReplyThatFailsWhileAnsweringIsNotAnsweredASecondTime() {
        val calls = Collections.synchronizedList(mutableListOf<String>())
        val reply = object : ChannelReply {
            override fun success(value: Any?) {
                calls.add("success")
                throw IllegalArgumentException("Unsupported value")
            }

            override fun error(code: String, message: String?) {
                calls.add("error")
            }
        }
        work.call("getApplications", reply) { 1 }
        drainBackground()

        // Must not throw on the UI thread either.
        ui.runPending()
        assertEquals(listOf("success"), calls)
    }

    @Test
    fun theUiStepRunsOnTheReplyExecutorWithTheBackgroundValue() {
        val reply = RecordingReply()
        val uiStepThread = AtomicReference<Thread>()
        work.callThen("installApk", reply, { 2 }) { value ->
            uiStepThread.set(Thread.currentThread())
            value * 10
        }
        drainBackground()
        ui.runPending()

        assertEquals(listOf("success:20"), reply.calls)
        assertSame(Thread.currentThread(), uiStepThread.get())
    }

    @Test
    fun aFailingUiStepBecomesOneErrorReply() {
        val reply = RecordingReply()
        work.callThen("installApk", reply, { 2 }) { throw IllegalStateException("no activity") }
        drainBackground()
        ui.runPending()

        assertEquals(listOf("error:native_error:no activity"), reply.calls)
    }

    @Test
    fun aReplyThatArrivesAfterCloseIsDropped() {
        val reply = RecordingReply()
        work.call("getApplications", reply) { "late" }
        drainBackground()
        work.close()
        ui.runPending()

        assertEquals(emptyList<String>(), reply.calls)
    }

    @Test
    fun aCallAfterCloseRunsNothingAndAnswersNothing() {
        val reply = RecordingReply()
        val ran = AtomicBoolean(false)
        work.close()
        background.shutdownNow()

        work.call("getApplications", reply) { ran.set(true) }
        ui.runPending()

        assertFalse(ran.get())
        assertEquals(emptyList<String>(), reply.calls)
    }

    @Test
    fun eventsAreDeliveredOnTheReplyExecutorInSubmissionOrder() {
        val delivered = Collections.synchronizedList(mutableListOf<String>())
        val deliveryThreads = Collections.synchronizedList(mutableListOf<Thread>())
        work.event("PACKAGE_ADDED", {
            Thread.sleep(100)
            "added"
        }) {
            deliveryThreads.add(Thread.currentThread())
            delivered.add(it)
        }
        work.event("PACKAGE_REMOVED", { "removed" }) {
            deliveryThreads.add(Thread.currentThread())
            delivered.add(it)
        }
        drainBackground()

        assertEquals(emptyList<String>(), delivered)
        ui.runPending()
        assertEquals(listOf("added", "removed"), delivered)
        assertEquals(listOf(Thread.currentThread(), Thread.currentThread()), deliveryThreads)
    }

    @Test
    fun aFailingEventIsDroppedAndLaterEventsStillArrive() {
        val delivered = Collections.synchronizedList(mutableListOf<String>())
        work.event<String>("PACKAGE_CHANGED", { throw IllegalStateException("gone") }) { delivered.add(it) }
        work.event("PACKAGE_REMOVED", { "removed" }) { delivered.add(it) }
        drainBackground()
        ui.runPending()

        assertEquals(listOf("removed"), delivered)
    }
}
