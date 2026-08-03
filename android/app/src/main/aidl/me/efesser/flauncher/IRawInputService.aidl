package me.efesser.flauncher;

import me.efesser.flauncher.IRawInputCallback;

/**
 * Transaction ids are spelled out because destroy() needs a fixed one, and aidl
 * insists that either every method carries an id or none does.
 */
interface IRawInputService {
    /** Starts reading every /dev/input node that reports key events. */
    void start(IRawInputCallback callback) = 1;

    void stop() = 2;

    /** Which input nodes were opened; empty when none could be read. */
    List<String> openedDevices() = 3;

    /**
     * Shizuku calls this to tear the helper process down. The id is fixed by
     * Shizuku and must not be changed.
     */
    void destroy() = 16777114;
}
