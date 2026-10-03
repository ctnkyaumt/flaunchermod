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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SettingsService> buildSettingsService() async =>
      SettingsService(await SharedPreferences.getInstance());

  test("setUse24HourTimeFormat", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    await settingsService.setUse24HourTimeFormat(true);

    expect(sharedPreferences.getBool("use_24_hour_time_format"), isTrue);
  });

  test("setGradientUuid", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    await settingsService.setGradientUuid("4730aa2d-1a90-49a6-9942-ffe82f470e26");

    expect(sharedPreferences.getString("gradient_uuid"), "4730aa2d-1a90-49a6-9942-ffe82f470e26");
  });

  group("setUnsplashAuthor", () {
    test("with value saves author info", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);

      await settingsService.setUnsplashAuthor("unsplash author");

      expect(sharedPreferences.getString("unsplash_author"), "unsplash author");
    });

    test("without value erases author info", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.setString("unsplash_author", "unsplash author");
      final settingsService = SettingsService(sharedPreferences);

      await settingsService.setUnsplashAuthor(null);

      expect(sharedPreferences.getString("unsplash_author"), isNull);
    });
  });

  test("unsplashEnabled is off without API credentials", () async {
    final settingsService = await buildSettingsService();

    expect(settingsService.unsplashEnabled, isFalse);
  });

  test("unsplashAuthor", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.setString("unsplash_author", "unsplash author");
    final settingsService = SettingsService(sharedPreferences);

    expect(settingsService.unsplashAuthor, "unsplash author");
  });

  group("getGradientUuid", () {
    test("without uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final settingsService = SettingsService(sharedPreferences);

      expect(settingsService.gradientUuid, null);
    });

    test("with uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      await sharedPreferences.setString("gradient_uuid", "4730aa2d-1a90-49a6-9942-ffe82f470e26");
      final settingsService = SettingsService(sharedPreferences);

      expect(settingsService.gradientUuid, "4730aa2d-1a90-49a6-9942-ffe82f470e26");
    });
  });

  group("getUse24HourTimeFormat", () {
    test("without value from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final settingsService = SettingsService(sharedPreferences);

      expect(settingsService.use24HourTimeFormat, isTrue);
    });

    test("with value from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      await sharedPreferences.setBool("use_24_hour_time_format", false);
      final settingsService = SettingsService(sharedPreferences);

      expect(settingsService.use24HourTimeFormat, isFalse);
    });
  });

  group("settings backup", () {
    test("exports portable weather units", () async {
      final settingsService = await buildSettingsService();
      await settingsService.setWeatherUnits(WeatherUnits.us);

      final weather = settingsService.exportSettings()["weather"] as Map<String, dynamic>;

      expect(weather["units"], "us");
      expect(weather["lat"], isNull);
      expect(settingsService.exportSettings()["gradientUuid"], isNull);
    });

    for (final units in [WeatherUnits.us, WeatherUnits.si]) {
      test("restores legacy $units units", () async {
        final settingsService = await buildSettingsService();

        await settingsService.restoreSettings({"weather": {"units": units.toString()}});

        expect(settingsService.weatherUnits, units);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString("weather_units"), units == WeatherUnits.us ? "us" : "si");
      });
    }

    test("restores integer coordinates as doubles", () async {
      final settingsService = await buildSettingsService();

      await settingsService.restoreSettings({"weather": {"lat": 51, "lon": -2}});

      expect(settingsService.weatherLatitude, 51.0);
      expect(settingsService.weatherLongitude, -2.0);
    });

    test("null metadata clears the previous gradient, author, and weather location", () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString("gradient_uuid", "old-gradient");
      await preferences.setString("unsplash_author", "old-author");
      await preferences.setString("weather_location_name", "old-city");
      await preferences.setDouble("weather_latitude", 51.0);
      await preferences.setDouble("weather_longitude", -2.0);
      final settingsService = SettingsService(preferences);

      await settingsService.restoreSettings({
        "gradientUuid": null,
        "unsplashAuthor": null,
        "weather": {"lat": null, "lon": null, "locationName": null},
      });

      expect(settingsService.gradientUuid, isNull);
      expect(settingsService.unsplashAuthor, isNull);
      expect(settingsService.weatherLocationName, isNull);
      expect(settingsService.weatherLatitude, isNull);
      expect(settingsService.weatherLongitude, isNull);
      for (final key in ["gradient_uuid", "unsplash_author", "weather_location_name",
        "weather_latitude", "weather_longitude"]) {
        expect(preferences.containsKey(key), isFalse);
      }
    });

    test("a rejected preference write fails restore", () async {
      SharedPreferencesStorePlatform.instance = _RejectingPreferencesStore();
      final settingsService = await buildSettingsService();

      await expectLater(
        settingsService.restoreSettings({"use24HourTimeFormat": false}),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _RejectingPreferencesStore extends InMemorySharedPreferencesStore {
  _RejectingPreferencesStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async => false;
}
