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

// Import stub implementation instead of Firebase packages
import 'package:flauncher/stubs/firebase_stubs.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _crashReportsEnabledKey = "crash_reports_enabled";
const _analyticsEnabledKey = "analytics_enabled";
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

enum WeatherUnits {
  si,
  us,
}

class SettingsService extends ChangeNotifier {
  final SharedPreferences _sharedPreferences;
  final FirebaseCrashlytics? _firebaseCrashlytics;
  final FirebaseAnalytics? _firebaseAnalytics;
  final FirebaseRemoteConfig _firebaseRemoteConfig;
  Timer? _remoteConfigRefreshTimer;

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

  SettingsService(
    this._sharedPreferences,
    this._firebaseCrashlytics,
    this._firebaseAnalytics,
    this._firebaseRemoteConfig,
  ) {
    // Initialize Firebase services if available
    // Removed Firebase initialization
    
    // Only set up remote config timer if Firebase is available
    if (_firebaseRemoteConfig != null) {
      _remoteConfigRefreshTimer = Timer.periodic(Duration(hours: 6, minutes: 1), (_) => _refreshFirebaseRemoteConfig());
    }
    
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
      notifyListeners();
    } catch (e) {
      debugPrint("Error restoring settings: $e");
      // Don't rethrow, just log and continue, as partial settings restore is better than none
    }
  }
}
