package me.efesser.flauncher

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AdbRetryPolicyTest {
    @Test
    fun immediateStreamFailuresExhaustRetriesDespiteSuccessfulHandshakes() {
        val policy = AdbRetryPolicy()
        val delays = (1..12).map { policy.nextDelay(10) }
        assertEquals(listOf(5_000L, 15_000L, 30_000L, 60_000L), delays.take(4))
        assertEquals(List(8) { 120_000L }, delays.drop(4))
        assertNull(policy.nextDelay(10))
    }

    @Test
    fun anIdleButStableStreamRestoresReconnectBudget() {
        val policy = AdbRetryPolicy()
        repeat(12) { policy.nextDelay(0) }
        assertEquals(5_000L, policy.nextDelay(30_000))
        assertEquals(15_000L, policy.nextDelay(0))
    }

    @Test
    fun manualConnectRestoresBudget() {
        val policy = AdbRetryPolicy()
        repeat(12) { policy.nextDelay(0) }
        assertNull(policy.nextDelay(29_999))
        policy.reset()
        assertEquals(5_000L, policy.nextDelay(0))
    }
}
