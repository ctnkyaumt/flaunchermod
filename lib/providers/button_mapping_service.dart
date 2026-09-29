/*
 * FLaunchermod
 * Copyright (C)
 * 2026 - ctnkyaumt
 * Forked from: 2021  Étienne Fesser
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

import 'dart:async';
import 'dart:convert';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key under which the whole mapping table is persisted.
///
/// The accessibility service reads this same entry straight out of the
/// `FlutterSharedPreferences` file, so the table is stored as one JSON string
/// rather than as a list — `shared_preferences` encodes lists with a prefix
/// scheme that is awkward to parse from Kotlin. Keep the two in sync with
/// `ButtonMappingStore` on the native side.
const _buttonMappingsKey = "button_mappings";

enum ButtonActionType {
  launchApp,
  openFlauncher,
  openSettings,
  block,
}

class ButtonAction {
  final ButtonActionType type;

  /// Only set when [type] is [ButtonActionType.launchApp].
  final String? packageName;

  /// Human-readable target, shown in the UI. Not read natively.
  final String? label;

  const ButtonAction({required this.type, this.packageName, this.label});

  Map<String, dynamic> toJson() => {
        "type": describeEnum(type),
        if (packageName != null) "packageName": packageName,
        if (label != null) "label": label,
      };

  static ButtonAction? fromJson(Map<String, dynamic> json) {
    final type = ButtonActionType.values
        .cast<ButtonActionType?>()
        .firstWhere((value) => describeEnum(value!) == json["type"], orElse: () => null);
    if (type == null) {
      return null;
    }
    return ButtonAction(
      type: type,
      packageName: json["packageName"] as String?,
      label: json["label"] as String?,
    );
  }

  String get description {
    switch (type) {
      case ButtonActionType.launchApp:
        return "Open ${label ?? packageName ?? "app"}";
      case ButtonActionType.openFlauncher:
        return "Open FLauncher";
      case ButtonActionType.openSettings:
        return "Open Android settings";
      case ButtonActionType.block:
        return "Do nothing";
    }
  }
}

/// How a button press is classified.
enum PressTrigger { single, doublePress, long }

extension PressTriggerLabel on PressTrigger {
  String get label {
    switch (this) {
      case PressTrigger.single:
        return "Single press";
      case PressTrigger.doublePress:
        return "Double press";
      case PressTrigger.long:
        return "Long press";
    }
  }
}

/// Which part of an Android `KeyEvent` identifies a mapped button.
///
/// Key codes are portable and remain the default. Some remotes collapse
/// several vendor buttons onto one Android key code, though; those buttons can
/// opt into their hardware scan code instead. Keeping this choice per mapping
/// avoids the all-or-nothing "use scan codes" switch used by other mappers.
enum KeyMatchMode { keyCode, scanCode }

/// Scan codes for remote buttons that report no usable key code.
///
/// Most TV remote extras come through as `KEYCODE_UNKNOWN`, so the scan code is
/// the only thing that tells them apart. Carried over from the earlier
/// button_mapping branch.
const _knownScanCodes = <int, String>{
  0x00000127: "Netflix",
  0x000c00a5: "YouTube",
  0x000c00a1: "Amazon Prime",
  0x000c0088: "Google Play",
  0x00070086: "Menu",
  0x000c0221: "Voice assistant",
};

/// Apps that TV remotes commonly carry a dedicated button for.
///
/// Offered as mapping targets whether or not they are installed: a button that
/// launches an app you removed is exactly the button worth remapping, and the
/// target may also be installed later.
const _remoteButtonApps = <String, String>{
  "com.netflix.ninja": "Netflix",
  "com.netflix.mediaclient": "Netflix",
  "com.google.android.youtube.tv": "YouTube",
  "com.google.android.youtube.tvmusic": "YouTube Music",
  "com.amazon.amazonvideo.livingroom": "Prime Video",
  "com.amazon.avod.thirdpartyclient": "Prime Video",
  "com.disney.disneyplus": "Disney+",
  "com.wbd.stream": "HBO Max",
  "com.spotify.tv.android": "Spotify",
  "com.apple.atve.androidtv.appletv": "Apple TV",
  "tv.twitch.android.app": "Twitch",
  "com.plexapp.android": "Plex",
  "tv.wuaki": "Rakuten TV",
  "com.google.android.videos": "Google TV",
};

/// An app that a button can be pointed at.
class AppTarget {
  final String packageName;
  final String name;

  /// False for the well-known remote apps that are not on this device.
  final bool installed;

  /// False when the app is installed but switched off in Android settings.
  final bool enabled;

  const AppTarget({
    required this.packageName,
    required this.name,
    this.installed = true,
    this.enabled = true,
  });

  String get status {
    if (!installed) return "Not installed";
    if (!enabled) return "Disabled";
    return packageName;
  }
}

/// A remote button and the actions bound to it.
class KeyMapping {
  final int keyCode;

  /// Hardware scan code, when the event carried one. It identifies unknown
  /// Android keys and can be selected explicitly when a remote reports one key
  /// code for several vendor buttons.
  final int? scanCode;

  final KeyMatchMode matchMode;

  /// Platform name for the key code, e.g. `KEYCODE_GUIDE`.
  final String? keyLabel;

  final ButtonAction? single;
  final ButtonAction? doublePress;
  final ButtonAction? long;

  const KeyMapping({
    required this.keyCode,
    this.scanCode,
    this.matchMode = KeyMatchMode.keyCode,
    this.keyLabel,
    this.single,
    this.doublePress,
    this.long,
  });

  bool get hasAny => single != null || doublePress != null || long != null;

  ButtonAction? actionFor(PressTrigger trigger) {
    switch (trigger) {
      case PressTrigger.single:
        return single;
      case PressTrigger.doublePress:
        return doublePress;
      case PressTrigger.long:
        return long;
    }
  }

  KeyMapping withAction(PressTrigger trigger, ButtonAction? action) => KeyMapping(
        keyCode: keyCode,
        scanCode: scanCode,
        matchMode: matchMode,
        keyLabel: keyLabel,
        single: trigger == PressTrigger.single ? action : single,
        doublePress: trigger == PressTrigger.doublePress ? action : doublePress,
        long: trigger == PressTrigger.long ? action : long,
      );

  /// Identity of the physical button, used to find an existing binding.
  ///
  /// Mirrors `ButtonMappingStore.Mappings.resolve` on the native side.
  String get id => matchMode == KeyMatchMode.scanCode ? "sc:$scanCode" : "kc:$keyCode";

  Map<String, dynamic> toJson() => {
        "keyCode": keyCode,
        if (scanCode != null) "scanCode": scanCode,
        "matchMode": describeEnum(matchMode),
        if (keyLabel != null) "keyLabel": keyLabel,
        if (single != null) "single": single!.toJson(),
        if (doublePress != null) "double": doublePress!.toJson(),
        if (long != null) "long": long!.toJson(),
      };

  static KeyMapping? fromJson(Map<String, dynamic> json) {
    final keyCode = json["keyCode"];
    if (keyCode is! int) {
      return null;
    }
    ButtonAction? action(String key) {
      final raw = json[key];
      return raw is Map ? ButtonAction.fromJson(Map<String, dynamic>.from(raw)) : null;
    }

    final scanCode = json["scanCode"];
    final matchMode = json["matchMode"] == describeEnum(KeyMatchMode.scanCode) ||
            // Existing mappings did not persist a mode. Preserve their old
            // behaviour: only KEYCODE_UNKNOWN fell back to the scan code.
            (!json.containsKey("matchMode") && keyCode == 0)
        ? KeyMatchMode.scanCode
        : KeyMatchMode.keyCode;
    if (matchMode == KeyMatchMode.scanCode && !(scanCode is int && scanCode != 0)) {
      return null;
    }

    final mapping = KeyMapping(
      keyCode: keyCode,
      scanCode: scanCode is int && scanCode != 0 ? scanCode : null,
      matchMode: matchMode,
      keyLabel: json["keyLabel"] as String?,
      single: action("single"),
      doublePress: action("double"),
      long: action("long"),
    );
    return mapping.hasAny ? mapping : null;
  }

  /// Friendly name for the button, falling back to the raw codes.
  String get displayName {
    final known = matchMode == KeyMatchMode.scanCode && scanCode != null
        ? _knownScanCodes[scanCode]
        : null;
    if (known != null) {
      return known;
    }

    final label = keyLabel;
    if (label != null && label.isNotEmpty && label != "KEYCODE_UNKNOWN") {
      // "KEYCODE_MEDIA_PLAY_PAUSE" -> "Media play pause"
      final stripped = label.startsWith("KEYCODE_") ? label.substring("KEYCODE_".length) : label;
      final words = stripped.replaceAll("_", " ").toLowerCase();
      if (words.isNotEmpty) {
        final friendly = "${words[0].toUpperCase()}${words.substring(1)}";
        return matchMode == KeyMatchMode.scanCode ? "$friendly (scan $scanCode)" : friendly;
      }
    }

    if (matchMode == KeyMatchMode.scanCode) {
      return "Button (scan $scanCode)";
    }
    return "Key $keyCode";
  }

  /// One-line summary of everything bound to this button.
  String get summary {
    final parts = <String>[
      for (final trigger in PressTrigger.values)
        if (actionFor(trigger) != null) "${trigger.label}: ${actionFor(trigger)!.description}",
    ];
    return parts.isEmpty ? "Nothing bound" : parts.join("\n");
  }
}

/// A button identified by its Linux key code, read straight off `/dev/input`.
///
/// This also covers buttons Android handles before dispatching to apps.
/// Reading them needs the shell input reader.
class RawMapping {
  final int code;

  /// HID usage reported in MSC_SCAN. Several vendor buttons may share code 240.
  final int? rawScanCode;

  /// The `/dev/input` node it came from, shown to help tell remotes apart.
  final String? device;

  final ButtonAction? single;
  final ButtonAction? doublePress;
  final ButtonAction? long;

  const RawMapping({
    required this.code,
    int? rawScanCode,
    this.device,
    this.single,
    this.doublePress,
    this.long,
  }) : rawScanCode = rawScanCode == 0 ? null : rawScanCode;

  bool get hasAny => single != null || doublePress != null || long != null;

  ButtonAction? actionFor(PressTrigger trigger) {
    switch (trigger) {
      case PressTrigger.single:
        return single;
      case PressTrigger.doublePress:
        return doublePress;
      case PressTrigger.long:
        return long;
    }
  }

  RawMapping withAction(PressTrigger trigger, ButtonAction? action) => RawMapping(
        code: code,
        rawScanCode: rawScanCode,
        device: device,
        single: trigger == PressTrigger.single ? action : single,
        doublePress: trigger == PressTrigger.doublePress ? action : doublePress,
        long: trigger == PressTrigger.long ? action : long,
      );

  Map<String, dynamic> toJson() => {
        "code": code,
        if (rawScanCode != null) "rawScanCode": rawScanCode,
        if (device != null) "device": device,
        if (single != null) "single": single!.toJson(),
        if (doublePress != null) "double": doublePress!.toJson(),
        if (long != null) "long": long!.toJson(),
      };

  static RawMapping? fromJson(Map<String, dynamic> json) {
    final code = json["code"];
    if (code is! int) {
      return null;
    }
    ButtonAction? action(String key) {
      final raw = json[key];
      return raw is Map ? ButtonAction.fromJson(Map<String, dynamic>.from(raw)) : null;
    }

    final mapping = RawMapping(
      code: code,
      rawScanCode: json["rawScanCode"] is int ? json["rawScanCode"] as int : null,
      device: json["device"] as String?,
      single: action("single"),
      doublePress: action("double"),
      long: action("long"),
    );
    return mapping.hasAny ? mapping : null;
  }

  String get id => rawScanCode == null ? "$code" : "$code:$rawScanCode";

  String get displayName => rawScanCode == null
      ? "Raw button $code"
      : "Raw button $code (usage 0x${rawScanCode!.toRadixString(16)})";

  String get summary {
    final parts = <String>[
      for (final trigger in PressTrigger.values)
        if (actionFor(trigger) != null) "${trigger.label}: ${actionFor(trigger)!.description}",
    ];
    return parts.isEmpty ? "Nothing bound" : parts.join("\n");
  }
}

/// Whether the shell-privileged helper that reads `/dev/input` can run.
enum ShizukuStatus { unavailable, permissionRequired, ready }

/// State of the launcher's own connection to the device's adbd.
enum AdbState { disconnected, connecting, connected, failed }

/// Which native input stream a capture dialog is waiting for.
///
/// Android and raw events are both broadcast while capture mode is armed. A
/// normal mapping must explicitly reject raw events, otherwise the faster
/// `/dev/input` reader can win the race and make a perfectly valid Android key
/// look unmappable.
enum ButtonCaptureSource { android, raw, any }

bool isButtonCaptureEvent(Map<dynamic, dynamic> event, ButtonCaptureSource source) {
  if (event["keyAction"] != 0) return false;
  final rawCode = event["rawCode"];
  final isRaw = rawCode is int && rawCode >= 0;
  switch (source) {
    case ButtonCaptureSource.android:
      return !isRaw;
    case ButtonCaptureSource.raw:
      return isRaw;
    case ButtonCaptureSource.any:
      return true;
  }
}

/// Owns one capture attempt so closing an old dialog cannot stop a newer one.
class ButtonCaptureSession {
  final Future<void> Function() _disarm;
  final _result = Completer<Map<String, dynamic>?>();
  StreamSubscription<dynamic>? _subscription;
  Timer? _timeout;
  Timer? _rawReleaseTimeout;
  Map<String, dynamic>? _rawPress;
  bool _finished = false;

  ButtonCaptureSession._(this._disarm);

  Future<Map<String, dynamic>?> get result => _result.future;

  void _start(
    Stream<dynamic> events,
    Future<void> Function() arm,
    Duration timeout,
    ButtonCaptureSource source,
  ) async {
    try {
      _subscription = events.listen(
        (event) {
          if (_finished) return;
          if (event is Map && event["captureCancelled"] == true) {
            _finish(null);
          } else if (event is Map && _rawPress != null) {
            final pressed = _rawPress!;
            if (event["keyAction"] == 1 && event["rawCode"] == pressed["rawCode"] &&
                event["rawScanCode"] == pressed["rawScanCode"] &&
                event["device"] == pressed["device"]) {
              _finish(pressed);
            }
          } else if (event is Map && isButtonCaptureEvent(event, source)) {
            final pressed = Map<String, dynamic>.from(event);
            if (event["rawCode"] is int && event["rawCode"] >= 0) {
              // Keep interception armed until this press ends. Its Android
              // copy can otherwise activate the next dialog's focused option.
              _rawPress = pressed;
              // Some firmware never sends UP; still finish within half a second.
              _rawReleaseTimeout = Timer(const Duration(milliseconds: 500), () => _finish(pressed));
            } else {
              _finish(pressed);
            }
          }
        },
        onError: (Object error) => _finish(null),
        onDone: () => _finish(null),
      );
      _timeout = Timer(timeout, () => _finish(null));
      await arm();
    } catch (e) {
      await _finish(null);
    }
  }

  Future<void> cancel() => _finish(null);

  Future<void> _finish(Map<String, dynamic>? event) async {
    if (_finished) return;
    _finished = true;
    _timeout?.cancel();
    _rawReleaseTimeout?.cancel();
    // Queue disarming before waiting for stream cancellation. A replacement
    // capture can then queue its arm after this stop, even during slow setup.
    final disarming = _disarm().catchError((Object error) {
      debugPrint("ButtonMappingService: could not stop capture - $error");
    });
    // Unsubscribing from the platform stream must not hold up the result.
    // Disarming is serialized; any late event is rejected by _finished.
    _subscription?.cancel().catchError((Object error) {
      debugPrint("ButtonMappingService: could not cancel capture stream - $error");
    });
    await disarming;
    _result.complete(event);
  }
}

/// Both routes to the shell privilege that reading `/dev/input` needs.
class RawInputStatus {
  final ShizukuStatus shizuku;
  final bool shizukuConnected;
  final AdbState adb;

  /// Last ADB failure, worth showing because the causes are all user-fixable.
  final String? adbError;

  /// Whether wireless-debugging pairing is offered as a setup option.
  /// An authorised TCP connection can also work without pairing.
  final bool pairingRequired;

  const RawInputStatus({
    this.shizuku = ShizukuStatus.unavailable,
    this.shizukuConnected = false,
    this.adb = AdbState.disconnected,
    this.adbError,
    this.pairingRequired = false,
  });

  /// Whether firmware buttons can be read right now.
  bool get ready => shizukuConnected || adb == AdbState.connected;

  static RawInputStatus fromMap(Map<dynamic, dynamic> map) => RawInputStatus(
        shizuku: _shizuku(map["shizuku"] as String?),
        shizukuConnected: map["shizukuConnected"] as bool? ?? false,
        adb: _adb(map["adb"] as String?),
        adbError: map["adbError"] as String?,
        pairingRequired: map["pairingRequired"] as bool? ?? false,
      );

  static ShizukuStatus _shizuku(String? name) {
    switch (name) {
      case "READY":
        return ShizukuStatus.ready;
      case "PERMISSION_REQUIRED":
        return ShizukuStatus.permissionRequired;
      default:
        return ShizukuStatus.unavailable;
    }
  }

  static AdbState _adb(String? name) {
    switch (name) {
      case "CONNECTED":
        return AdbState.connected;
      case "CONNECTING":
        return AdbState.connecting;
      case "FAILED":
        return AdbState.failed;
      default:
        return AdbState.disconnected;
    }
  }
}

/// Fallback for app shortcut buttons whose key events cannot be intercepted.
/// It redirects whenever the source app comes to the foreground, including
/// when the user opens that app without its remote button.
class AppRedirect {
  final String sourcePackage;

  /// Display name of the app the button normally opens.
  final String? sourceLabel;
  final ButtonAction action;

  const AppRedirect({required this.sourcePackage, this.sourceLabel, required this.action});

  Map<String, dynamic> toJson() => {
        "sourcePackage": sourcePackage,
        if (sourceLabel != null) "sourceLabel": sourceLabel,
        "action": action.toJson(),
      };

  static AppRedirect? fromJson(Map<String, dynamic> json) {
    final sourcePackage = json["sourcePackage"];
    if (sourcePackage is! String || sourcePackage.isEmpty) {
      return null;
    }
    final action = ButtonAction.fromJson(Map<String, dynamic>.from(json["action"] ?? {}));
    if (action == null) {
      return null;
    }
    return AppRedirect(
      sourcePackage: sourcePackage,
      sourceLabel: json["sourceLabel"] as String?,
      action: action,
    );
  }

  String get displayName => sourceLabel ?? sourcePackage;
}

class ButtonMappingService extends ChangeNotifier {
  final SharedPreferences _sharedPreferences;
  final FLauncherChannel _channel;
  late final Stream<dynamic> _keyEvents = _channel.keyCaptureStream;
  ButtonCaptureSession? _captureSession;
  Future<void> _captureModeChanges = Future<void>.value();
  bool _disposed = false;

  List<KeyMapping> _keyMappings = [];
  List<AppRedirect> _appRedirects = [];
  List<RawMapping> _rawMappings = [];
  bool _serviceEnabled = false;
  RawInputStatus _rawInputStatus = const RawInputStatus();

  List<KeyMapping> get keyMappings => List.unmodifiable(_keyMappings);

  List<AppRedirect> get appRedirects => List.unmodifiable(_appRedirects);

  List<RawMapping> get rawMappings => List.unmodifiable(_rawMappings);

  RawInputStatus get rawInputStatus => _rawInputStatus;

  /// Whether the accessibility service is switched on in Android settings.
  /// Nothing is intercepted until it is.
  bool get serviceEnabled => _serviceEnabled;

  ButtonMappingService(this._sharedPreferences, this._channel) {
    _load();
    refreshServiceState();
    refreshRawInputStatus();
  }

  @override
  void dispose() {
    _disposed = true;
    _captureSession?.cancel();
    super.dispose();
  }

  void _load() {
    final raw = _sharedPreferences.getString(_buttonMappingsKey);
    if (raw == null) {
      return;
    }
    try {
      final root = jsonDecode(raw) as Map<String, dynamic>;
      _keyMappings = ((root["keyMappings"] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => KeyMapping.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<KeyMapping>()
          .toList();
      _appRedirects = ((root["appRedirects"] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => AppRedirect.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<AppRedirect>()
          .toList();
      _rawMappings = ((root["rawMappings"] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => RawMapping.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<RawMapping>()
          .toList();
    } catch (e) {
      debugPrint("ButtonMappingService: could not parse stored mappings - $e");
    }
  }

  Future<void> _persist() async {
    final payload = jsonEncode({
      "keyMappings": _keyMappings.map((mapping) => mapping.toJson()).toList(),
      "appRedirects": _appRedirects.map((redirect) => redirect.toJson()).toList(),
      "rawMappings": _rawMappings.map((mapping) => mapping.toJson()).toList(),
    });
    await _sharedPreferences.setString(_buttonMappingsKey, payload);
    // The service also watches the preferences file, but the broadcast makes
    // the reload immediate rather than dependent on listener delivery.
    await _channel.notifyButtonMappingsChanged();
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshServiceState() async {
    final enabled = await _channel.isButtonMapperEnabled();
    if (_disposed) return;
    if (enabled != _serviceEnabled) {
      _serviceEnabled = enabled;
      notifyListeners();
    }
  }

  Future<void> refreshRawInputStatus() async {
    RawInputStatus status;
    try {
      status = RawInputStatus.fromMap(await _channel.rawInputStatus());
    } catch (e) {
      status = const RawInputStatus();
    }
    if (_disposed) return;
    final changed = status.shizuku != _rawInputStatus.shizuku ||
        status.shizukuConnected != _rawInputStatus.shizukuConnected ||
        status.adb != _rawInputStatus.adb ||
        status.adbError != _rawInputStatus.adbError ||
        status.pairingRequired != _rawInputStatus.pairingRequired;
    _rawInputStatus = status;
    if (changed) notifyListeners();
  }

  /// Pairs with the device's own adbd, then brings the connection up.
  Future<bool> pairWithAdb(int port, String code) async {
    bool paired;
    try {
      paired = await _channel.adbPair(port, code);
    } catch (e) {
      debugPrint("ButtonMappingService: ADB pairing failed - $e");
      paired = false;
    }
    if (paired) {
      try {
        await _channel.startRawInput();
        await _waitForRawInput();
      } catch (e) {
        debugPrint("ButtonMappingService: paired but could not start raw input - $e");
        await refreshRawInputStatus();
      }
    } else {
      await refreshRawInputStatus();
    }
    return paired;
  }

  /// Asks the accessibility service to connect without pairing, which is all
  /// that is needed before Android 11 or once a key is already authorised.
  Future<void> connectRawInput() async {
    try {
      await _channel.startRawInput();
    } catch (e) {
      debugPrint("ButtonMappingService: could not start raw input - $e");
      await refreshRawInputStatus();
      return;
    }
    await _waitForRawInput();
  }

  /// Binding Shizuku and opening an ADB stream both finish after the method
  /// channel call returns. Poll briefly so the page transitions from Connect
  /// to Map without requiring the user to leave and reopen it.
  Future<void> _waitForRawInput() async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    do {
      if (_disposed) return;
      await refreshRawInputStatus();
      if (_disposed || _rawInputStatus.ready || _rawInputStatus.adb == AdbState.failed) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } while (!_disposed && DateTime.now().isBefore(deadline));
  }

  /// Shows Shizuku's own consent dialog when permission is not held yet. The
  /// answer arrives asynchronously, so callers should refresh afterwards.
  Future<void> requestShizukuPermission() async {
    try {
      await _channel.requestShizukuPermission();
    } catch (e) {
      debugPrint("ButtonMappingService: Shizuku permission request failed - $e");
    }
    await refreshRawInputStatus();
  }

  /// The `/dev/input` nodes the helper opened. Empty means it is not running.
  Future<List<String>> shizukuInputDevices() async {
    try {
      return (await _channel.shizukuInputDevices()).whereType<String>().toList();
    } catch (e) {
      return [];
    }
  }

  /// Binds [action] to one trigger of a raw button, dropping the mapping once
  /// nothing is left on it.
  Future<void> setRawAction({
    required int code,
    int? rawScanCode,
    String? device,
    required PressTrigger trigger,
    required ButtonAction? action,
  }) async {
    final candidate = RawMapping(code: code, rawScanCode: rawScanCode, device: device);
    final index = _rawMappings.indexWhere((existing) => existing.id == candidate.id);
    final updated = (index == -1 ? candidate : _rawMappings[index]).withAction(trigger, action);

    final next = [..._rawMappings];
    if (index == -1) {
      if (updated.hasAny) next.add(updated);
    } else if (updated.hasAny) {
      next[index] = updated;
    } else {
      next.removeAt(index);
    }
    _rawMappings = next;
    await _persist();
  }

  Future<void> removeRawMapping(RawMapping mapping) async {
    _rawMappings = _rawMappings.where((existing) => existing.id != mapping.id).toList();
    await _persist();
  }

  /// False when the device has no settings screen we could reach.
  Future<bool> openAccessibilitySettings() => _channel.openAccessibilitySettings();

  /// Everything a button can be pointed at: every installed app including the
  /// disabled ones, plus the well-known remote apps that are missing entirely.
  Future<List<AppTarget>> mappableApplications() async {
    final targets = <String, AppTarget>{};
    try {
      for (final entry in await _channel.getMappableApplications()) {
        if (entry is! Map) continue;
        final packageName = entry["packageName"];
        if (packageName is! String || packageName.isEmpty) continue;
        targets[packageName] = AppTarget(
          packageName: packageName,
          name: (entry["name"] as String?)?.trim().isNotEmpty == true
              ? entry["name"] as String
              : packageName,
          enabled: entry["enabled"] as bool? ?? true,
        );
      }
    } catch (e) {
      debugPrint("ButtonMappingService: could not list applications - $e");
    }

    // Only fill in a well-known app when the device really does not have it.
    // Tracked by name as we go, so the several package names one app ships
    // under do not each add their own entry.
    final seenNames = targets.values.map((target) => target.name.toLowerCase()).toSet();
    _remoteButtonApps.forEach((packageName, name) {
      if (targets.containsKey(packageName) || !seenNames.add(name.toLowerCase())) {
        return;
      }
      targets[packageName] = AppTarget(packageName: packageName, name: name, installed: false);
    });

    // Installed first, then the ones that are only known by name.
    return targets.values.toList()
      ..sort((a, b) {
        if (a.installed != b.installed) return a.installed ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  /// Every key event the accessibility service sees while capture mode is on.
  /// Used by the button test screen to show what a remote actually emits.
  Stream<dynamic> get keyEvents => _keyEvents;

  Future<void> setCaptureMode(bool enabled) {
    final change = _captureModeChanges.then((_) => _channel.setKeyCaptureMode(enabled));
    // A failed arm must not prevent its cleanup or the next capture attempt.
    _captureModeChanges = change.catchError((Object error) {});
    return change;
  }

  ButtonCaptureSession startKeyCapture({
    Duration timeout = const Duration(seconds: 10),
    ButtonCaptureSource source = ButtonCaptureSource.android,
  }) {
    _captureSession?.cancel();
    late final ButtonCaptureSession session;
    session = ButtonCaptureSession._(() {
      if (!identical(_captureSession, session)) return Future<void>.value();
      _captureSession = null;
      return setCaptureMode(false);
    });
    _captureSession = session;
    session._start(keyEvents, () => setCaptureMode(true), timeout, source);
    return session;
  }

  /// Puts the service into capture mode and completes with the first button
  /// pressed, or null if [timeout] elapses first.
  ///
  /// Capture mode swallows every button while active, so it must always be
  /// turned back off — including when the caller gives up.
  Future<Map<String, dynamic>?> captureNextKey({
    Duration timeout = const Duration(seconds: 10),
    ButtonCaptureSource source = ButtonCaptureSource.android,
  }) => startKeyCapture(timeout: timeout, source: source).result;

  /// Binds [action] to one trigger of a button, leaving its other triggers
  /// alone. Passing a null action clears just that trigger, and the whole
  /// binding is dropped once nothing is left on it.
  Future<void> setKeyAction({
    required int keyCode,
    int? scanCode,
    KeyMatchMode matchMode = KeyMatchMode.keyCode,
    String? keyLabel,
    required PressTrigger trigger,
    required ButtonAction? action,
  }) async {
    final candidate = KeyMapping(
      keyCode: keyCode,
      scanCode: scanCode,
      matchMode: matchMode,
      keyLabel: keyLabel,
    );
    final index = _keyMappings.indexWhere((existing) => existing.id == candidate.id);

    final updated =
        (index == -1 ? candidate : _keyMappings[index]).withAction(trigger, action);

    final next = [..._keyMappings];
    if (index == -1) {
      if (updated.hasAny) next.add(updated);
    } else if (updated.hasAny) {
      next[index] = updated;
    } else {
      next.removeAt(index);
    }
    _keyMappings = next;
    await _persist();
  }

  Future<void> removeKeyMapping(KeyMapping mapping) async {
    _keyMappings = _keyMappings.where((existing) => existing.id != mapping.id).toList();
    await _persist();
  }

  Future<void> setAppRedirect(String sourcePackage, String? sourceLabel, ButtonAction action) async {
    final redirect =
        AppRedirect(sourcePackage: sourcePackage, sourceLabel: sourceLabel, action: action);
    final index = _appRedirects.indexWhere((existing) => existing.sourcePackage == sourcePackage);
    if (index == -1) {
      _appRedirects = [..._appRedirects, redirect];
    } else {
      _appRedirects = [..._appRedirects]..[index] = redirect;
    }
    await _persist();
  }

  Future<void> removeAppRedirect(String sourcePackage) async {
    _appRedirects =
        _appRedirects.where((redirect) => redirect.sourcePackage != sourcePackage).toList();
    await _persist();
  }
}
