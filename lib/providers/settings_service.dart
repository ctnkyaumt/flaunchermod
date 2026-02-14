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

import 'dart:async';
import 'dart:convert';

// Import stub implementation instead of Firebase packages
import 'package:flauncher/stubs/firebase_stubs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _use24HourTimeFormatKey = "use_24_hour_time_format";
const _appHighlightAnimationEnabledKey = "app_highlight_animation_enabled";
const _gradientUuidKey = "gradient_uuid";
const _unsplashEnabledKey = "unsplash_enabled";
const _unsplashAuthorKey = "unsplash_author";

const _weatherEnabledKey = "weather_enabled";
const _weatherLatitudeKey = "weather_latitude";
const _weatherLongitudeKey = "weather_longitude";
const _weatherLocationNameKey = "weather_location_name";
const _weatherShowDetailsKey = "weather_show_details";
const _weatherShowCityKey = "weather_show_city";
const _weatherUnitsKey = "weather_units";
const _weatherRefreshIntervalMinutesKey = "weather_refresh_interval_minutes";
const _startupPermissionsCompletedKey = "startup_permissions_completed";
const _remoteKeyMapKey = "remote_key_map_v1";
const _remoteBindingsKey = "remote_bindings_v1";
const _remoteBindingsDefaultsKey = "remote_bindings_defaults_v1";
const _remoteKeyMapDefaultsKey = "remote_key_map_defaults_v1";
const _remoteDefaultsVersionKey = "remote_defaults_version_v1";
const _remoteDefaultsVersion = 2;

enum WeatherUnits {
  si,
  us,
}

enum RemoteKeyAction {
  up,
  down,
  left,
  right,
  select,
  back,
  openSettings,
}

extension RemoteKeyActionX on RemoteKeyAction {
  String get id {
    switch (this) {
      case RemoteKeyAction.up:
        return 'up';
      case RemoteKeyAction.down:
        return 'down';
      case RemoteKeyAction.left:
        return 'left';
      case RemoteKeyAction.right:
        return 'right';
      case RemoteKeyAction.select:
        return 'select';
      case RemoteKeyAction.back:
        return 'back';
      case RemoteKeyAction.openSettings:
        return 'openSettings';
    }
  }

  String get label {
    switch (this) {
      case RemoteKeyAction.up:
        return 'Up';
      case RemoteKeyAction.down:
        return 'Down';
      case RemoteKeyAction.left:
        return 'Left';
      case RemoteKeyAction.right:
        return 'Right';
      case RemoteKeyAction.select:
        return 'Select / OK';
      case RemoteKeyAction.back:
        return 'Back';
      case RemoteKeyAction.openSettings:
        return 'Open settings';
    }
  }
}

enum RemoteBindingType {
  navigateUp,
  navigateDown,
  navigateLeft,
  navigateRight,
  select,
  back,
  openSettings,
  openAndroidSettings,
  openWifiSettings,
  takeScreenshot,
  launchApp,
}

extension RemoteBindingTypeX on RemoteBindingType {
  String get id {
    switch (this) {
      case RemoteBindingType.navigateUp:
        return 'navigateUp';
      case RemoteBindingType.navigateDown:
        return 'navigateDown';
      case RemoteBindingType.navigateLeft:
        return 'navigateLeft';
      case RemoteBindingType.navigateRight:
        return 'navigateRight';
      case RemoteBindingType.select:
        return 'select';
      case RemoteBindingType.back:
        return 'back';
      case RemoteBindingType.openSettings:
        return 'openSettings';
      case RemoteBindingType.openAndroidSettings:
        return 'openAndroidSettings';
      case RemoteBindingType.openWifiSettings:
        return 'openWifiSettings';
      case RemoteBindingType.takeScreenshot:
        return 'takeScreenshot';
      case RemoteBindingType.launchApp:
        return 'launchApp';
    }
  }

  String get label {
    switch (this) {
      case RemoteBindingType.navigateUp:
        return 'Navigate up';
      case RemoteBindingType.navigateDown:
        return 'Navigate down';
      case RemoteBindingType.navigateLeft:
        return 'Navigate left';
      case RemoteBindingType.navigateRight:
        return 'Navigate right';
      case RemoteBindingType.select:
        return 'Select / OK';
      case RemoteBindingType.back:
        return 'Back';
      case RemoteBindingType.openSettings:
        return 'Open settings';
      case RemoteBindingType.openAndroidSettings:
        return 'Android settings';
      case RemoteBindingType.openWifiSettings:
        return 'Open Wi‑Fi settings';
      case RemoteBindingType.takeScreenshot:
        return 'Take screenshot';
      case RemoteBindingType.launchApp:
        return 'Launch app';
    }
  }

  static RemoteBindingType? tryParse(String id) {
    for (final t in RemoteBindingType.values) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }
}

class RemoteBinding {
  final int keyCode;
  final int? scanCode;
  final RemoteBindingType type;
  final String? packageName;

  const RemoteBinding({
    required this.keyCode,
    this.scanCode,
    required this.type,
    this.packageName,
  });

  String get keyId {
    final sc = scanCode ?? 0;
    if (sc != 0) {
      return 'sc:$sc';
    }
    return 'kc:$keyCode';
  }

  RemoteBinding copyWith({
    int? keyCode,
    int? scanCode,
    RemoteBindingType? type,
    String? packageName,
    bool clearPackageName = false,
  }) {
    return RemoteBinding(
      keyCode: keyCode ?? this.keyCode,
      scanCode: scanCode ?? this.scanCode,
      type: type ?? this.type,
      packageName: clearPackageName ? null : (packageName ?? this.packageName),
    );
  }

  Map<String, dynamic> toJson() => {
        'keyCode': keyCode,
        if (scanCode != null) 'scanCode': scanCode,
        'type': type.id,
        if (packageName != null) 'packageName': packageName,
      };

  static RemoteBinding? fromJson(dynamic json) {
    if (json is! Map) {
      return null;
    }
    final rawKeyCode = json['keyCode'];
    final rawScanCode = json['scanCode'];
    final rawType = json['type'];
    if (rawKeyCode is! int || rawType is! String) {
      return null;
    }
    final type = RemoteBindingTypeX.tryParse(rawType);
    if (type == null) {
      return null;
    }
    final packageName = json['packageName'];
    return RemoteBinding(
      keyCode: rawKeyCode,
      scanCode: rawScanCode is int ? rawScanCode : null,
      type: type,
      packageName: packageName is String ? packageName : null,
    );
  }
}

class SettingsService extends ChangeNotifier {
  final SharedPreferences _sharedPreferences;
  final FirebaseRemoteConfig _firebaseRemoteConfig;
  Timer? _remoteConfigRefreshTimer;

  List<RemoteBinding> get shippedRemoteBindings => const [
        RemoteBinding(keyCode: 19, type: RemoteBindingType.navigateUp),
        RemoteBinding(keyCode: 20, type: RemoteBindingType.navigateDown),
        RemoteBinding(keyCode: 21, type: RemoteBindingType.navigateLeft),
        RemoteBinding(keyCode: 22, type: RemoteBindingType.navigateRight),
        RemoteBinding(keyCode: 23, type: RemoteBindingType.select),
        RemoteBinding(keyCode: 66, type: RemoteBindingType.select),
        RemoteBinding(keyCode: 4, type: RemoteBindingType.back),
        RemoteBinding(keyCode: 176, type: RemoteBindingType.openAndroidSettings),
        RemoteBinding(keyCode: 82, type: RemoteBindingType.openAndroidSettings),
      ];

  Map<String, int> get shippedRemoteKeyMap => const {};

  bool get crashReportsEnabled => false; // Always disabled

  bool get analyticsEnabled => false; // Always disabled

  bool get use24HourTimeFormat => _sharedPreferences.getBool(_use24HourTimeFormatKey) ?? true;

  bool get appHighlightAnimationEnabled => _sharedPreferences.getBool(_appHighlightAnimationEnabledKey) ?? true;

  String? get gradientUuid => _sharedPreferences.getString(_gradientUuidKey);

  bool get unsplashEnabled => _firebaseRemoteConfig.getBool(_unsplashEnabledKey);

  String? get unsplashAuthor => _sharedPreferences.getString(_unsplashAuthorKey);

  bool get weatherEnabled => _sharedPreferences.getBool(_weatherEnabledKey) ?? false;

  double? get weatherLatitude {
    final value = _sharedPreferences.getDouble(_weatherLatitudeKey);
    return value;
  }

  double? get weatherLongitude {
    final value = _sharedPreferences.getDouble(_weatherLongitudeKey);
    return value;
  }

  String? get weatherLocationName => _sharedPreferences.getString(_weatherLocationNameKey);

  bool get weatherShowDetails => _sharedPreferences.getBool(_weatherShowDetailsKey) ?? false;

  bool get weatherShowCity => _sharedPreferences.getBool(_weatherShowCityKey) ?? true;

  WeatherUnits get weatherUnits {
    final raw = _sharedPreferences.getString(_weatherUnitsKey);
    switch (raw) {
      case 'us':
        return WeatherUnits.us;
      case 'si':
      default:
        return WeatherUnits.si;
    }
  }

  int get weatherRefreshIntervalMinutes {
    final raw = _sharedPreferences.getInt(_weatherRefreshIntervalMinutesKey);
    if (raw == null) {
      return 60;
    }
    final clamped = raw < 15 ? 15 : (raw > 120 ? 120 : raw);
    final normalized = ((clamped / 15).round() * 15);
    return normalized < 15 ? 15 : (normalized > 120 ? 120 : normalized);
  }

  bool get startupPermissionsCompleted => _sharedPreferences.getBool(_startupPermissionsCompletedKey) ?? false;

  Map<String, int> get remoteKeyMap {
    final raw = _sharedPreferences.getString(_remoteKeyMapKey);
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const {};
      }
      final out = <String, int>{};
      for (final entry in decoded.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is String && v is int) {
          out[k] = v;
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  int? remoteKeyCode(RemoteKeyAction action) => remoteKeyMap[action.id];

  List<RemoteBinding> get remoteBindings {
    final raw = _sharedPreferences.getString(_remoteBindingsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final out = <RemoteBinding>[];
      for (final item in decoded) {
        final binding = RemoteBinding.fromJson(item);
        if (binding != null) {
          out.add(binding);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  RemoteBinding? remoteBindingForAndroidKeyEvent({required int keyCode, required int scanCode}) {
    if (scanCode != 0) {
      for (final binding in remoteBindings) {
        if (binding.scanCode != null && binding.scanCode == scanCode) {
          return binding;
        }
      }
    }

    for (final binding in remoteBindings) {
      if (binding.keyCode == keyCode) {
        return binding;
      }
    }
    return null;
  }

  Future<void> upsertRemoteBinding(RemoteBinding binding) async {
    final next = <RemoteBinding>[];
    bool replaced = false;
    for (final existing in remoteBindings) {
      if (existing.keyId == binding.keyId) {
        next.add(binding);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) {
      next.add(binding);
    }
    await _sharedPreferences.setString(_remoteBindingsKey, jsonEncode(next.map((b) => b.toJson()).toList()));
    notifyListeners();
  }

  Future<void> removeRemoteBinding(RemoteBinding binding) async {
    final next = remoteBindings.where((b) => b.keyId != binding.keyId).toList(growable: false);
    await _sharedPreferences.setString(_remoteBindingsKey, jsonEncode(next.map((b) => b.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _ensureRemoteDefaultsSaved() async {
    final existingVersion = _sharedPreferences.getInt(_remoteDefaultsVersionKey);
    final shouldOverwrite = existingVersion == null || existingVersion != _remoteDefaultsVersion;

    final existingBindingsDefaults = _sharedPreferences.getString(_remoteBindingsDefaultsKey);
    if (shouldOverwrite || existingBindingsDefaults == null || existingBindingsDefaults.isEmpty) {
      await _sharedPreferences.setString(
        _remoteBindingsDefaultsKey,
        jsonEncode(shippedRemoteBindings.map((b) => b.toJson()).toList()),
      );
    }

    final existingKeyMapDefaults = _sharedPreferences.getString(_remoteKeyMapDefaultsKey);
    if (shouldOverwrite || existingKeyMapDefaults == null || existingKeyMapDefaults.isEmpty) {
      await _sharedPreferences.setString(_remoteKeyMapDefaultsKey, jsonEncode(shippedRemoteKeyMap));
    }

    if (shouldOverwrite) {
      await _sharedPreferences.setInt(_remoteDefaultsVersionKey, _remoteDefaultsVersion);
    }
  }

  Future<void> resetRemoteControlsToDefaults() async {
    final bindingsDefaultsRaw = _sharedPreferences.getString(_remoteBindingsDefaultsKey);
    final keyMapDefaultsRaw = _sharedPreferences.getString(_remoteKeyMapDefaultsKey);

    final bindingsToRestore = (bindingsDefaultsRaw == null || bindingsDefaultsRaw.isEmpty)
        ? jsonEncode(shippedRemoteBindings.map((b) => b.toJson()).toList())
        : bindingsDefaultsRaw;
    final keyMapToRestore = (keyMapDefaultsRaw == null || keyMapDefaultsRaw.isEmpty)
        ? jsonEncode(shippedRemoteKeyMap)
        : keyMapDefaultsRaw;

    await _sharedPreferences.setString(_remoteBindingsKey, bindingsToRestore);
    await _sharedPreferences.setString(_remoteKeyMapKey, keyMapToRestore);
    notifyListeners();
  }

  SettingsService(
    this._sharedPreferences,
    FirebaseCrashlytics? firebaseCrashlytics,
    FirebaseAnalytics? firebaseAnalytics,
    this._firebaseRemoteConfig,
  ) {
    // Initialize Firebase services if available
    // Removed Firebase initialization
    
    _remoteConfigRefreshTimer = Timer.periodic(Duration(hours: 6, minutes: 1), (_) => _refreshFirebaseRemoteConfig());
    
    () async {
      await _ensureRemoteDefaultsSaved();
    }();

    debugPrint("SettingsService initialized");
  }

  @override
  void dispose() {
    _remoteConfigRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> setCrashReportsEnabled(bool value) async {
    // No-op - permanently disabled
    notifyListeners();
  }

  Future<void> setAnalyticsEnabled(bool value) async {
    // No-op - permanently disabled
    notifyListeners();
  }

  Future<void> setUse24HourTimeFormat(bool value) async {
    await _sharedPreferences.setBool(_use24HourTimeFormatKey, value);
    notifyListeners();
  }

  Future<void> setAppHighlightAnimationEnabled(bool value) async {
    await _sharedPreferences.setBool(_appHighlightAnimationEnabledKey, value);
    notifyListeners();
  }

  Future<void> setGradientUuid(String value) async {
    await _sharedPreferences.setString(_gradientUuidKey, value);
    notifyListeners();
  }

  Future<void> setUnsplashAuthor(String? value) async {
    if (value == null) {
      await _sharedPreferences.remove(_unsplashAuthorKey);
    } else {
      await _sharedPreferences.setString(_unsplashAuthorKey, value);
    }
    notifyListeners();
  }

  Future<void> setWeatherEnabled(bool value) async {
    await _sharedPreferences.setBool(_weatherEnabledKey, value);
    notifyListeners();
  }

  Future<void> setWeatherCoordinates({double? latitude, double? longitude}) async {
    if (latitude == null) {
      await _sharedPreferences.remove(_weatherLatitudeKey);
    } else {
      await _sharedPreferences.setDouble(_weatherLatitudeKey, latitude);
    }

    if (longitude == null) {
      await _sharedPreferences.remove(_weatherLongitudeKey);
    } else {
      await _sharedPreferences.setDouble(_weatherLongitudeKey, longitude);
    }

    notifyListeners();
  }

  Future<void> setWeatherLocationName(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _sharedPreferences.remove(_weatherLocationNameKey);
    } else {
      await _sharedPreferences.setString(_weatherLocationNameKey, value);
    }
    notifyListeners();
  }

  Future<void> setWeatherShowDetails(bool value) async {
    await _sharedPreferences.setBool(_weatherShowDetailsKey, value);
    notifyListeners();
  }

  Future<void> setWeatherShowCity(bool value) async {
    await _sharedPreferences.setBool(_weatherShowCityKey, value);
    notifyListeners();
  }

  Future<void> setWeatherUnits(WeatherUnits units) async {
    final raw = units == WeatherUnits.us ? 'us' : 'si';
    await _sharedPreferences.setString(_weatherUnitsKey, raw);
    notifyListeners();
  }

  Future<void> setWeatherRefreshIntervalMinutes(int minutes) async {
    final clamped = minutes < 15 ? 15 : (minutes > 120 ? 120 : minutes);
    final normalized = ((clamped / 15).round() * 15);
    final saved = normalized < 15 ? 15 : (normalized > 120 ? 120 : normalized);
    await _sharedPreferences.setInt(_weatherRefreshIntervalMinutesKey, saved);
    notifyListeners();
  }

  Future<void> setStartupPermissionsCompleted(bool value) async {
    await _sharedPreferences.setBool(_startupPermissionsCompletedKey, value);
    notifyListeners();
  }

  Future<void> setRemoteKeyCode(RemoteKeyAction action, int? keyCode) async {
    final next = Map<String, int>.from(remoteKeyMap);
    if (keyCode == null) {
      next.remove(action.id);
    } else {
      next[action.id] = keyCode;
    }
    await _sharedPreferences.setString(_remoteKeyMapKey, jsonEncode(next));
    notifyListeners();
  }

  Future<void> setRemoteKeyMap(Map<String, int> keyMap) async {
    await _sharedPreferences.setString(_remoteKeyMapKey, jsonEncode(keyMap));
    notifyListeners();
  }

  LogicalKeyboardKey? mapAndroidKeyEvent(int keyCode, int scanCode) {
    final bound = remoteBindingForAndroidKeyEvent(keyCode: keyCode, scanCode: scanCode);
    if (bound != null) {
      switch (bound.type) {
        case RemoteBindingType.navigateUp:
          return LogicalKeyboardKey.arrowUp;
        case RemoteBindingType.navigateDown:
          return LogicalKeyboardKey.arrowDown;
        case RemoteBindingType.navigateLeft:
          return LogicalKeyboardKey.arrowLeft;
        case RemoteBindingType.navigateRight:
          return LogicalKeyboardKey.arrowRight;
        case RemoteBindingType.select:
          return LogicalKeyboardKey.select;
        case RemoteBindingType.back:
          return LogicalKeyboardKey.gameButtonB;
        case RemoteBindingType.openSettings:
          return LogicalKeyboardKey.f1;
        case RemoteBindingType.openAndroidSettings:
        case RemoteBindingType.openWifiSettings:
        case RemoteBindingType.takeScreenshot:
        case RemoteBindingType.launchApp:
          return null;
      }
    }

    if (remoteKeyCode(RemoteKeyAction.up) == keyCode) return LogicalKeyboardKey.arrowUp;
    if (remoteKeyCode(RemoteKeyAction.down) == keyCode) return LogicalKeyboardKey.arrowDown;
    if (remoteKeyCode(RemoteKeyAction.left) == keyCode) return LogicalKeyboardKey.arrowLeft;
    if (remoteKeyCode(RemoteKeyAction.right) == keyCode) return LogicalKeyboardKey.arrowRight;
    if (remoteKeyCode(RemoteKeyAction.select) == keyCode) return LogicalKeyboardKey.select;
    if (remoteKeyCode(RemoteKeyAction.back) == keyCode) return LogicalKeyboardKey.gameButtonB;
    if (remoteKeyCode(RemoteKeyAction.openSettings) == keyCode) return LogicalKeyboardKey.f1;
    return null;
  }

  bool isSelectEvent(RawKeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
      return true;
    }

    final data = event.data;
    if (data is RawKeyEventDataAndroid) {
      final binding = remoteBindingForAndroidKeyEvent(keyCode: data.keyCode, scanCode: data.scanCode);
      if (binding != null && binding.type == RemoteBindingType.select) {
        return true;
      }
      final mapped = remoteKeyCode(RemoteKeyAction.select);
      if (mapped != null && data.keyCode == mapped) {
        return true;
      }
    }

    return false;
  }

  Future<void> _refreshFirebaseRemoteConfig() async {
    bool updated = false;
    try {
      updated = await _firebaseRemoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint("Could not refresh Firebase Remote Config: $e");
    }
    if (updated) {
      notifyListeners();
    }
  }

  Future<void> restoreSettings(Map<String, dynamic> data) async {
    try {
      if (data.containsKey("use24HourTimeFormat")) {
        final val = data["use24HourTimeFormat"];
        if (val is bool) await _sharedPreferences.setBool(_use24HourTimeFormatKey, val);
      }
      if (data.containsKey("appHighlightAnimationEnabled")) {
        final val = data["appHighlightAnimationEnabled"];
        if (val is bool) await _sharedPreferences.setBool(_appHighlightAnimationEnabledKey, val);
      }
      if (data.containsKey("gradientUuid")) {
        final val = data["gradientUuid"];
        if (val is String) await _sharedPreferences.setString(_gradientUuidKey, val);
      }
      
      if (data.containsKey("weather")) {
        final w = data["weather"];
        if (w is Map<String, dynamic>) {
          if (w.containsKey("enabled")) {
             final val = w["enabled"];
             if (val is bool) await _sharedPreferences.setBool(_weatherEnabledKey, val);
          }
          if (w.containsKey("lat")) {
             final val = w["lat"];
             if (val is double) await _sharedPreferences.setDouble(_weatherLatitudeKey, val);
          }
          if (w.containsKey("lon")) {
             final val = w["lon"];
             if (val is double) await _sharedPreferences.setDouble(_weatherLongitudeKey, val);
          }
          if (w.containsKey("locationName")) {
             final val = w["locationName"];
             if (val is String) await _sharedPreferences.setString(_weatherLocationNameKey, val);
          }
          if (w.containsKey("showDetails")) {
             final val = w["showDetails"];
             if (val is bool) await _sharedPreferences.setBool(_weatherShowDetailsKey, val);
          }
          if (w.containsKey("showCity")) {
             final val = w["showCity"];
             if (val is bool) await _sharedPreferences.setBool(_weatherShowCityKey, val);
          }
          if (w.containsKey("units")) {
             final val = w["units"];
             if (val is String) await _sharedPreferences.setString(_weatherUnitsKey, val);
          }
          if (w.containsKey("refreshInterval")) {
             final val = w["refreshInterval"];
             if (val is int) await _sharedPreferences.setInt(_weatherRefreshIntervalMinutesKey, val);
          }
        }
      }

      if (data.containsKey("remoteKeys")) {
        final raw = data["remoteKeys"];
        if (raw is Map) {
          final next = <String, int>{};
          for (final entry in raw.entries) {
            final k = entry.key;
            final v = entry.value;
            if (k is String && v is int) {
              next[k] = v;
            }
          }
          await setRemoteKeyMap(next);
        }
      }

      if (data.containsKey("remoteBindings")) {
        final raw = data["remoteBindings"];
        if (raw is List) {
          final next = <RemoteBinding>[];
          for (final item in raw) {
            final binding = RemoteBinding.fromJson(item);
            if (binding != null) {
              next.add(binding);
            }
          }
          await _sharedPreferences.setString(_remoteBindingsKey, jsonEncode(next.map((b) => b.toJson()).toList()));
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error restoring settings: $e");
      // Don't rethrow, just log and continue, as partial settings restore is better than none
    }
  }
}
