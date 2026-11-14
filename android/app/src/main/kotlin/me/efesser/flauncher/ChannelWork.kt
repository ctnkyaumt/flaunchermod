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

import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** The answer side of one method-channel call, without Flutter types. */
internal interface ChannelReply {
    fun success(value: Any?)
    fun error(code: String, message: String?)
}

/**
 * Decides where a channel call runs: the work on [background], the answer on
 * [replies] (the UI thread in the app).
 *
 * Every call gets exactly one answer: the value, or an error carrying the
 * exception's message. After [close] nothing more runs or is answered, so a
 * call still in flight when the activity goes away is simply dropped.
 *
 * Give it a single-thread [background] executor (see [newBackgroundExecutor]):
 * calls and package events then run, and are answered, in the order they came.
 */
internal class ChannelWork(
    private val background: Executor,
    private val replies: Executor,
    private val log: (String, Throwable) -> Unit = { _, _ -> },
) {
    @Volatile
    private var closed = false

    /** Runs [work] in the background and answers [reply] with its value. */
    fun call(method: String, reply: ChannelReply, errorCode: String = NATIVE_ERROR, work: () -> Any?) {
        dispatch(method, reply, errorCode, work) { it }
    }

    /**
     * Runs [work] in the background, then [then] with its value on the reply
     * executor, and answers [reply] with what [then] returns. For calls that
     * must start an activity after slow preparation.
     */
    fun <T> callThen(method: String, reply: ChannelReply, work: () -> T, then: (T) -> Any?) {
        dispatch(method, reply, NATIVE_ERROR, work, then)
    }

    private fun <T> dispatch(
        method: String,
        reply: ChannelReply,
        errorCode: String,
        work: () -> T,
        then: (T) -> Any?,
    ) {
        val answered = AtomicBoolean(false)
        fun answer(action: () -> Unit) {
            if (!answered.compareAndSet(false, true)) return
            try {
                action()
            } catch (e: Exception) {
                // The reply itself failed (an unencodable value, say). A second
                // answer would only make Flutter throw "Reply already submitted".
                log("MethodChannel reply failed ($method): ${e.message}", e)
            }
        }
        fun fail(e: Exception) {
            log("MethodChannel error ($method): ${e.message}", e)
            answer { reply.error(errorCode, e.message) }
        }
        submit(
            work,
            onValue = deliver@{ value ->
                val result = try {
                    then(value)
                } catch (e: Exception) {
                    fail(e)
                    return@deliver
                }
                answer { reply.success(result) }
            },
            onFailure = { e -> fail(e) },
        )
    }

    /**
     * Computes [work] in the background and hands the value to [deliver] on the
     * reply executor. A failure is logged and nothing is delivered.
     */
    fun <T> event(name: String, work: () -> T, deliver: (T) -> Unit) {
        submit(
            work,
            onValue = { value ->
                try {
                    deliver(value)
                } catch (e: Exception) {
                    log("Event delivery failed ($name): ${e.message}", e)
                }
            },
            onFailure = { e -> log("Event error ($name): ${e.message}", e) },
        )
    }

    /** Stops running and answering anything; later calls are ignored. */
    fun close() {
        closed = true
    }

    private fun <T> submit(work: () -> T, onValue: (T) -> Unit, onFailure: (Exception) -> Unit) {
        if (closed) return
        try {
            background.execute {
                if (closed) return@execute
                val value = try {
                    work()
                } catch (e: Exception) {
                    onReplyThread { onFailure(e) }
                    return@execute
                }
                onReplyThread { onValue(value) }
            }
        } catch (e: RejectedExecutionException) {
            onReplyThread { onFailure(e) }
        }
    }

    private fun onReplyThread(action: () -> Unit) {
        if (closed) return
        try {
            replies.execute {
                if (!closed) action()
            }
        } catch (e: RejectedExecutionException) {
            // Nowhere left to answer.
        }
    }

    companion object {
        const val NATIVE_ERROR = "native_error"

        /** One daemon thread, so work keeps its order and never holds the process up. */
        fun newBackgroundExecutor(): ExecutorService = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "flauncher-channel").apply { isDaemon = true }
        }
    }
}
