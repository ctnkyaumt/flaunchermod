package me.efesser.flauncher

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.EventChannel.EventSink

object RemoteKeyEventRelay {
    @Volatile
    var sink: EventSink? = null

    fun emit(origin: String, event: KeyEvent) {
        sink?.success(
            mapOf(
                "origin" to origin,
                "action" to when (event.action) {
                    KeyEvent.ACTION_DOWN -> "down"
                    KeyEvent.ACTION_UP -> "up"
                    else -> "other"
                },
                "keyCode" to event.keyCode,
                "scanCode" to event.scanCode,
                "repeatCount" to event.repeatCount,
                "deviceId" to event.deviceId,
                "source" to event.source,
                "flags" to event.flags,
                "metaState" to event.metaState,
                "eventTime" to event.eventTime
            )
        )
    }
}

class RemoteKeyAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        serviceInfo = info
        super.onServiceConnected()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        RemoteKeyEventRelay.emit("accessibility", event)
        return false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {}

    override fun onInterrupt() {}
}
