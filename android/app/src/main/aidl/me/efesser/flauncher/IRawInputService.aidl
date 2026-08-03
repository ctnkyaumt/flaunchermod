package me.efesser.flauncher;

import me.efesser.flauncher.IRawInputCallback;

interface IRawInputService {
    /** Starts reading every /dev/input node that reports key events. */
    void start(IRawInputCallback callback);

    void stop();

    /** Which input nodes were opened; empty when none could be read. */
    List<String> openedDevices();

    /**
     * Shizuku calls this to tear the helper process down. The transaction id is
     * fixed by Shizuku and must not be changed.
     */
    void destroy() = 16777114;
}
