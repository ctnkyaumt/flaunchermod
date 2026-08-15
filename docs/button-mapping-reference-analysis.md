# Button Mapper reference analysis

This analysis covers the button-remapping architecture of the supplied
`button.apkm`; it is not a source-code import. FLaunchermod's implementation is
independent and does not include the reference app's code or native binaries.

## Artifact

- App: Button Mapper (`flar2.homebutton`)
- Version: 4.09 (409), Android 8.1+
- Bundle size: 9,881,280 bytes
- SHA-256: `73BC7718003819CFA25CC786F51A7B36CA802F556B0684A16B07BAA1C05599B0`
- Contents inspected: base APK, manifest/resources, DEX output, ARM64 native
  helpers, and ADB setup scripts

## Input architecture

| Path | Purpose | Important behavior |
| --- | --- | --- |
| Accessibility service | Normal buttons while any app is foreground | Requests `flagRequestFilterKeyEvents`, receives `onKeyEvent`, and consumes handled events |
| Android key code | Portable default identity | Used for normal and well-known buttons |
| Hardware scan code | Troubleshooting identity | Optional fallback when multiple vendor buttons share a key code; unknown key codes always fall back to scan codes |
| Native `keyeventd` helper | Advanced/screen-off raw input | Reads `/dev/input`, watches device-node hot-plug with inotify, and reports code/value pairs through an authenticated loopback socket |
| Shizuku user service | Privileged setup and actions | Copies/starts the raw helper and executes shell commands; it is not the ordinary key-capture path |
| ADB scripts | Privileged fallback | Grants permissions or starts the helper; the low-latency helper must be restarted after each reboot |

The reference treats accessibility events and raw kernel events as separate
sources. Raw observation does not imply that the original firmware action was
consumed. It also exposes key-code versus scan-code matching as an explicit
choice because either identity can be correct for a particular remote.

Single, double, and long presses are classified in the accessibility service,
which remains alive when the UI is not. FLaunchermod now runs unambiguous single
actions on key down; more complex bindings wait only when they need to
distinguish another trigger.

## Changes applied to FLaunchermod

- Normal capture now rejects raw `/dev/input` events, and firmware capture
  rejects Android events. Previously the raw event usually arrived first and
  made `Map a button` reject a valid press as unidentified.
- Each Android mapping now records whether it matches by key code or scan code.
  Existing mappings retain their prior behavior, while new mappings can use a
  scan code without changing or breaking every other mapping.
- A single-only mapping executes on key down. This reduces latency and supports
  buttons that never send a matching key-up event.
- An unrelated key-up can no longer cancel another button's long-press timer.
- The Shizuku raw reader watches `/dev/input` for Bluetooth/USB device hot-plug
  instead of taking a one-time snapshot at service startup.
- The ADB bridge no longer attempts to persistently expose adbd on TCP 5555.
  Older devices accurately report that `adb tcpip 5555` is required again after
  a reboot, matching Android's and the reference app's lifecycle.

The app-launch redirect remains a fallback for firmware buttons when raw input
is unavailable. It is intentionally described as a redirect, not true input
interception.
