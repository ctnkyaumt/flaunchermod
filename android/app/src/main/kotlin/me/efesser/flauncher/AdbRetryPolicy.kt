package me.efesser.flauncher

/** A successful handshake is not evidence that the input stream is usable. */
internal class AdbRetryPolicy {
    companion object {
        private val DELAYS_MS = longArrayOf(5_000, 15_000, 30_000, 60_000, 120_000)
        private const val MAX_RETRIES = 12
        private const val STABLE_STREAM_MS = 30_000L
    }

    private var retries = 0

    fun reset() {
        retries = 0
    }

    /** Reset only after a stream survives, including an idle getevent stream. */
    fun nextDelay(connectedForMs: Long): Long? {
        if (connectedForMs >= STABLE_STREAM_MS) reset()
        if (retries >= MAX_RETRIES) return null
        return DELAYS_MS[retries.coerceAtMost(DELAYS_MS.lastIndex)].also { retries++ }
    }
}
