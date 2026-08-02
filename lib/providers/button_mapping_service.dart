/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

  /// Hardware scan code, when the event carried one. Only used to tell apart
  /// buttons that report `KEYCODE_UNKNOWN`; a scan code is specific to one
  /// input device, so it is not what identifies a button that has a key code.
  final int? scanCode;

  /// Platform name for the key code, e.g. `KEYCODE_GUIDE`.
  final String? keyLabel;

  final ButtonAction? single;
  final ButtonAction? doublePress;
  final ButtonAction? long;

  const KeyMapping({
    required this.keyCode,
    this.scanCode,
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
        keyLabel: keyLabel,
        single: trigger == PressTrigger.single ? action : single,
        doublePress: trigger == PressTrigger.doublePress ? action : doublePress,
        long: trigger == PressTrigger.long ? action : long,
      );

  /// Identity of the physical button, used to find an existing binding.
  ///
  /// Mirrors `ButtonMappingStore.Mappings.resolve`: the key code identifies the
  /// button whenever there is one, and the scan code only stands in for the
  /// extra buttons that report `KEYCODE_UNKNOWN`.
  String get id => keyCode != 0 ? "kc:$keyCode" : "sc:$scanCode";

  Map<String, dynamic> toJson() => {
        "keyCode": keyCode,
        if (scanCode != null) "scanCode": scanCode,
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
    final mapping = KeyMapping(
      keyCode: keyCode,
      scanCode: scanCode is int && scanCode != 0 ? scanCode : null,
      keyLabel: json["keyLabel"] as String?,
      single: action("single"),
      doublePress: action("double"),
      long: action("long"),
    );
    return mapping.hasAny ? mapping : null;
  }

  /// Friendly name for the button, falling back to the raw codes.
  String get displayName {
    final known = keyCode == 0 && scanCode != null ? _knownScanCodes[scanCode] : null;
    if (known != null) {
      return known;
    }

    final label = keyLabel;
    if (label != null && label.isNotEmpty && label != "KEYCODE_UNKNOWN") {
      // "KEYCODE_MEDIA_PLAY_PAUSE" -> "Media play pause"
      final stripped = label.startsWith("KEYCODE_") ? label.substring("KEYCODE_".length) : label;
      final words = stripped.replaceAll("_", " ").toLowerCase();
      if (words.isNotEmpty) {
        return "${words[0].toUpperCase()}${words.substring(1)}";
      }
    }

    return scanCode != null ? "Button (scan $scanCode)" : "Key $keyCode";
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

/// A button the firmware wires straight to an app launch — the Netflix, YouTube
/// and Prime Video buttons on most TV remotes. These emit no key code at all,
/// so they are caught by noticing the app come to the foreground.
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

  List<KeyMapping> _keyMappings = [];
  List<AppRedirect> _appRedirects = [];
  bool _serviceEnabled = false;

  List<KeyMapping> get keyMappings => List.unmodifiable(_keyMappings);

  List<AppRedirect> get appRedirects => List.unmodifiable(_appRedirects);

  /// Whether the accessibility service is switched on in Android settings.
  /// Nothing is intercepted until it is.
  bool get serviceEnabled => _serviceEnabled;

  ButtonMappingService(this._sharedPreferences, this._channel) {
    _load();
    refreshServiceState();
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
    } catch (e) {
      debugPrint("ButtonMappingService: could not parse stored mappings - $e");
    }
  }

  Future<void> _persist() async {
    final payload = jsonEncode({
      "keyMappings": _keyMappings.map((mapping) => mapping.toJson()).toList(),
      "appRedirects": _appRedirects.map((redirect) => redirect.toJson()).toList(),
    });
    await _sharedPreferences.setString(_buttonMappingsKey, payload);
    // The service also watches the preferences file, but the broadcast makes
    // the reload immediate rather than dependent on listener delivery.
    await _channel.notifyButtonMappingsChanged();
    notifyListeners();
  }

  Future<void> refreshServiceState() async {
    final enabled = await _channel.isButtonMapperEnabled();
    if (enabled != _serviceEnabled) {
      _serviceEnabled = enabled;
      notifyListeners();
    }
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
  Stream<dynamic> get keyEvents => _channel.keyCaptureStream;

  Future<void> setCaptureMode(bool enabled) => _channel.setKeyCaptureMode(enabled);

  /// Puts the service into capture mode and completes with the first button
  /// pressed, or null if [timeout] elapses first.
  ///
  /// Capture mode swallows every button while active, so it must always be
  /// turned back off — including when the caller gives up.
  Future<Map<String, dynamic>?> captureNextKey({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // Subscribe before arming capture mode, otherwise a very fast press could
    // land between the two and be lost.
    final captured = _channel.keyCaptureStream.first.timeout(timeout);
    await _channel.setKeyCaptureMode(true);
    try {
      final event = await captured;
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return null;
    } catch (e) {
      // Timed out, or the stream closed without delivering anything.
      return null;
    } finally {
      await _channel.setKeyCaptureMode(false);
    }
  }

  /// Binds [action] to one trigger of a button, leaving its other triggers
  /// alone. Passing a null action clears just that trigger, and the whole
  /// binding is dropped once nothing is left on it.
  Future<void> setKeyAction({
    required int keyCode,
    int? scanCode,
    String? keyLabel,
    required PressTrigger trigger,
    required ButtonAction? action,
  }) async {
    final candidate = KeyMapping(keyCode: keyCode, scanCode: scanCode, keyLabel: keyLabel);
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
