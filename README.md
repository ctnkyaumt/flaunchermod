# FLauncher
FLauncher is an open-source alternative launcher for Android TV, built with [Flutter](https://flutter.dev).

## Features
- [x] No ads
- [x] Customizable categories
- [x] Manually reorder apps within categories
- [x] Open "Android Settings"
- [x] Open "App info"
- [x] Uninstall app
- [x] Clock
- [x] Wifi icon for quick access
- [x] Switch between row and grid for categories
- [x] Support for non-TV (sideloaded) apps + menu to download popular apps for ease of use
- [x] Navigation sound feedback
- [x] HDMI inputs page/section
- [x] Weather widget
- [x] Button mapper integrated (under settings) — remaps remote buttons, including
      the app shortcut buttons (Netflix, YouTube, ...). Home and Power are handled
      by Android itself and cannot be remapped. See the
      [input architecture notes](docs/button-mapping-reference-analysis.md).
- [x] Backup/restore (local only)
- [ ] Force stop app

## Remap Netflix, YouTube and other app buttons

Open **Settings > Button Mapping** and enable FLauncher's accessibility service.
Use **Test remote buttons**, then **Map a button** if an Android key is shown.
Choose the replacement app yourself in the action picker.

If only a raw event appears, connect the input reader and use **Map a firmware
button**. On a TV already connected to a computer through ADB, press **Connect**
and accept FLauncher's debugging prompt. TCP ADB also works on Android 11+; a
wireless-debugging pairing code is an alternative when supported. If necessary,
run `adb tcpip 5555` from the computer again after a reboot.

Raw mappings preserve the hardware usage code so Bluetooth factory buttons that
all report `KEY_UNKNOWN` can have different actions. Raw reading observes the
button; it cannot consume the firmware's original action. If that action still
opens an app, disable that particular app in Android settings, or use **Redirect
an app button** while keeping the original app installed and enabled. Redirects
also apply when opening that original app manually.

When upgrading from the old `0.0.4` mapper, enable the new FLauncher accessibility
service again. Existing launcher layout and other app data are kept by an update.

## Screenshots
|--|--|--|--|
| ![](screenshots/flauncher_screenshot_1770919020951.png) | ![](screenshots/flauncher_screenshot_1770919029766.png) | ![](screenshots/flauncher_screenshot_1770919074287.png) | ![](screenshots/flauncher_screenshot_1770919082051.png) |

## Set FLauncher as default launcher

### Method 1: remap another button
Android handles the Home button internally and never dispatches it to apps, so it
cannot be remapped without root. Instead, use the button mapper under settings (of
flauncher) to point a different remote button — a colour button, Guide, or one of the
app shortcut buttons — at FLauncher. This requires enabling FLauncher's accessibility
service, which the button mapper screen links to.

### Method 2: disable the default launcher
**:warning: Disclaimer :warning:**

**You are doing this at your own risk, and you'll be responsible in any case of malfunction on your device.**

The following commands have been tested on Chromecast with Google TV only. This may be different on other devices.

Once the default launcher is disabled, press the Home button on the remote, and you'll be prompted by the system to choose which app to set as default.

#### Disable default launcher
```shell
# Disable com.google.android.apps.tv.launcherx which is the default launcher on CCwGTV
$ adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
# com.google.android.tungsten.setupwraith will then be used as a 'fallback' and will automatically
# re-enable the default launcher, so disable it as well
$ adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
```

#### Re-enable default launcher
```shell
$ adb shell pm enable com.google.android.apps.tv.launcherx
$ adb shell pm enable com.google.android.tungsten.setupwraith
```

#### Known issues
On Chromecast with Google TV (maybe others), the "YouTube" remote button will stop working if the default launcher is disabled. As a workaround, you can use [Button Mapper](https://play.google.com/store/apps/details?id=flar2.homebutton) to remap it correctly.

## Wallpaper
Because Android's `WallpaperManager` is not available on some Android TV devices, FLauncher implements its own wallpaper management method.

Please note that changing wallpaper requires a file explorer to be installed on the device in order to pick a file.

<a href="https://www.buymeacoffee.com/etienn01" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="200"></a>
