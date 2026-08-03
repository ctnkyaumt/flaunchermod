package me.efesser.flauncher;

/** Raw key events read straight off /dev/input by the Shizuku helper. */
oneway interface IRawInputCallback {
    /**
     * @param code   Linux key code from the input event (EV_KEY).
     * @param value  0 released, 1 pressed, 2 auto-repeat.
     * @param device the /dev/input node the event came from.
     */
    void onRawKey(int code, int value, String device);
}
