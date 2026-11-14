/*
 * FLaunchermod
 * originally by efesser (30 May 2021)
 * ctnkyaumt 2026
 * Copyright (C) 2021 Étienne Fesser
 * Copyright (C) 2026 ctnkyaumt
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
import 'package:flauncher/providers/button_mapping/button_capture_session.dart';
import 'package:flauncher/providers/button_mapping/button_mapping_format.dart';
import 'package:flauncher/providers/button_mapping/button_mapping_model.dart';
import 'package:flauncher/providers/button_mapping/raw_input_status.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The model, the capture session and the raw-input status live in
// providers/button_mapping/. They are re-exported so that this file stays the
// one import for everything about button mapping.
export 'package:flauncher/providers/button_mapping/button_capture_session.dart';
export 'package:flauncher/providers/button_mapping/button_mapping_model.dart';
export 'package:flauncher/providers/button_mapping/raw_input_status.dart';

/// Key under which the whole mapping table is persisted.
///
/// The accessibility service reads this same entry straight out of the
/// `FlutterSharedPreferences` file, so the table is stored as one JSON string
/// rather than as a list — `shared_preferences` encodes lists with a prefix
/// scheme that is awkward to parse from Kotlin. Keep the two in sync with
/// `ButtonMappingStore` on the native side.
const _buttonMappingsKey = "button_mappings";

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
      final root = ButtonMappingFormat.decodeRoot(raw);
      _keyMappings = ButtonMappingFormat.decodeKeyMappings(root);
      _appRedirects = ButtonMappingFormat.decodeAppRedirects(root);
      _rawMappings = ButtonMappingFormat.decodeRawMappings(root);
    } catch (e) {
      debugPrint("ButtonMappingService: could not parse stored mappings - $e");
    }
  }

  Future<void> _persist() async {
    final payload = jsonEncode(exportMappings());
    if (!await _sharedPreferences.setString(_buttonMappingsKey, payload)) {
      throw StateError("Unable to save button mappings");
    }
    // The service also watches the preferences file, but the broadcast makes
    // the reload immediate rather than dependent on listener delivery.
    await _channel.notifyButtonMappingsChanged();
    if (!_disposed) notifyListeners();
  }

  Map<String, dynamic> exportMappings() => ButtonMappingFormat.encode(
        keyMappings: _keyMappings,
        appRedirects: _appRedirects,
        rawMappings: _rawMappings,
      );

  static void validateBackupMappings(Map<String, dynamic> data) =>
      ButtonMappingFormat.validateBackup(data);

  Future<void> restoreMappings(Map<String, dynamic> data) async {
    validateBackupMappings(data);
    _keyMappings = (data["keyMappings"] as List)
        .map((entry) => KeyMapping.fromJson(entry as Map<String, dynamic>)!).toList();
    _appRedirects = (data["appRedirects"] as List)
        .map((entry) => AppRedirect.fromJson(entry as Map<String, dynamic>)!).toList();
    _rawMappings = (data["rawMappings"] as List)
        .map((entry) => RawMapping.fromJson(entry as Map<String, dynamic>)!).toList();
    await _persist();
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
    final changed = status.differsFrom(_rawInputStatus);
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
  /// Capture sessions filter this stream by input source.
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
    session = ButtonCaptureSession(() {
      if (!identical(_captureSession, session)) return Future<void>.value();
      _captureSession = null;
      return setCaptureMode(false);
    });
    _captureSession = session;
    session.start(keyEvents, () => setCaptureMode(true), timeout, source);
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
