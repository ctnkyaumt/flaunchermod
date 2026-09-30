package me.efesser.flauncher

/** Keeps capture filtering consistent when a dialog opens between a key's edges. */
internal class CaptureKeyState {
    enum class Decision { CAPTURE, CONSUME, PASS_THROUGH }

    private val keysDown = mutableSetOf<String>()

    fun onKey(identity: String, action: Int, repeatCount: Int, capturing: Boolean): Decision {
        if (action == ACTION_UP) {
            // A DOWN that reached Android must also release Android's repeat state.
            if (!keysDown.remove(identity)) return Decision.PASS_THROUGH
            return if (capturing) Decision.CAPTURE else Decision.CONSUME
        }
        if (capturing) {
            if (action == ACTION_DOWN) ownDown(identity, repeatCount)
            return Decision.CAPTURE
        }
        if (action == ACTION_DOWN) {
            if (repeatCount > 0 && identity in keysDown) return Decision.CONSUME
            keysDown.remove(identity)
        }
        return Decision.PASS_THROUGH
    }

    fun ownDown(identity: String, repeatCount: Int) {
        // A repeat may belong to the OK press that opened capture.
        if (repeatCount == 0) keysDown.add(identity)
    }

    private companion object {
        const val ACTION_DOWN = 0
        const val ACTION_UP = 1
    }
}
