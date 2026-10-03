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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _use24HourTimeFormatKey = "use_24_hour_time_format";
const _appHighlightAnimationEnabledKey = "app_highlight_animation_enabled";
const _gradientUuidKey = "gradient_uuid";
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

enum WeatherUnits {
  si,
  us,
}

class SettingsService extends ChangeNotifier {
  final SharedPreferences _sharedPreferences;

  bool get use24HourTimeFormat => _sharedPreferences.getBool(_use24HourTimeFormatKey) ?? true;

  bool get appHighlightAnimationEnabled => _sharedPreferences.getBool(_appHighlightAnimationEnabledKey) ?? true;

  String? get gradientUuid => _sharedPreferences.getString(_gradientUuidKey);

  /// The Unsplash wallpaper source needs API credentials that this build does
  /// not ship, so the entry point stays hidden.
  bool get unsplashEnabled => false;

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

  SettingsService(this._sharedPreferences);

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

  Map<String, dynamic> exportSettings() => {
        "use24HourTimeFormat": use24HourTimeFormat,
        "appHighlightAnimationEnabled": appHighlightAnimationEnabled,
        "gradientUuid": gradientUuid,
        "unsplashAuthor": unsplashAuthor,
        "weather": {
          "enabled": weatherEnabled,
          "lat": weatherLatitude,
          "lon": weatherLongitude,
          "locationName": weatherLocationName,
          "showDetails": weatherShowDetails,
          "showCity": weatherShowCity,
          "units": weatherUnits == WeatherUnits.us ? "us" : "si",
          "refreshInterval": weatherRefreshIntervalMinutes,
        },
      };

  Future<void> restoreSettings(Map<String, dynamic> data) async {
    Future<void> write(Future<bool> result) async {
      if (!await result) throw StateError("Unable to save restored settings");
    }
    Future<void> restoreValues(Map<String, dynamic> source, Map<String, String> keys) async {
      for (final entry in keys.entries) {
        if (!source.containsKey(entry.key)) continue;
        final value = source[entry.key];
        if (value == null) {
          await write(_sharedPreferences.remove(entry.value));
        } else if (value is bool) {
          await write(_sharedPreferences.setBool(entry.value, value));
        } else if (value is String) {
          await write(_sharedPreferences.setString(entry.value, value));
        } else if (value is num) {
          await write(_sharedPreferences.setDouble(entry.value, value.toDouble()));
        }
      }
    }
    await restoreValues(data, {
      "use24HourTimeFormat": _use24HourTimeFormatKey,
      "appHighlightAnimationEnabled": _appHighlightAnimationEnabledKey,
      "gradientUuid": _gradientUuidKey,
      "unsplashAuthor": _unsplashAuthorKey,
    });
    final weather = data["weather"];
    if (weather is Map<String, dynamic>) {
      await restoreValues(weather, {
        "enabled": _weatherEnabledKey,
        "lat": _weatherLatitudeKey,
        "lon": _weatherLongitudeKey,
        "locationName": _weatherLocationNameKey,
        "showDetails": _weatherShowDetailsKey,
        "showCity": _weatherShowCityKey,
      });
      final units = weather["units"];
      if (units == 'us' || units == 'WeatherUnits.us') {
        await write(_sharedPreferences.setString(_weatherUnitsKey, 'us'));
      } else if (units == 'si' || units == 'WeatherUnits.si') {
        await write(_sharedPreferences.setString(_weatherUnitsKey, 'si'));
      }
      final minutes = weather["refreshInterval"];
      if (minutes is int) {
        final clamped = minutes.clamp(15, 120);
        final normalized = (clamped / 15).round() * 15;
        await write(_sharedPreferences.setInt(_weatherRefreshIntervalMinutesKey, normalized));
      }
    }
    notifyListeners();
  }
}
