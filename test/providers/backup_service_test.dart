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
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transparent_image/transparent_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FLauncherDatabase database;
  late SettingsService settings;
  late ButtonMappingService mappings;
  late _MemoryWallpaper wallpaper;
  late _BackupChannel channel;
  late BackupService backup;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = FLauncherDatabase.inMemory();
    settings = SettingsService(await SharedPreferences.getInstance());
    channel = _BackupChannel();
    mappings = ButtonMappingService(await SharedPreferences.getInstance(), channel);
    wallpaper = _MemoryWallpaper();
    backup = BackupService(database, settings, buttonMappings: mappings, wallpaper: wallpaper, channel: channel);
    await database.persistApps([AppsCompanion.insert(
      packageName: "installed.app", name: "Local app", version: "5",
      sideloaded: Value(true), isSystemApp: Value(true), icon: Value(Uint8List.fromList([7])),
    )]);
    await database.insertCategory(CategoriesCompanion.insert(id: Value(1), name: "Original", order: 0));
    await database.insertAppsCategories([AppsCategoriesCompanion.insert(
      categoryId: 1, appPackageName: "installed.app", order: 0,
    )]);
  });
  tearDown(() async {
    mappings.dispose();
    wallpaper.dispose();
    settings.dispose();
    await database.close();
  });

  Future<Map<String, dynamic>> snapshot() async => jsonDecode(await backup.createBackupContent()) as Map<String, dynamic>;

  test("v2 round trip preserves layout, weather, wallpaper and every mapping kind", () async {
    await settings.setWeatherUnits(WeatherUnits.us);
    await settings.setWeatherCoordinates(latitude: 41, longitude: 29);
    await wallpaper.restoreWallpaper(kTransparentImage);
    await mappings.restoreMappings({
      "keyMappings": [{"keyCode": 172, "scanCode": 314, "matchMode": "scanCode", "single": {"type": "openFlauncher"}}],
      "rawMappings": [
        {"code": 240, "rawScanCode": 786597, "device": "/dev/input/event2", "single": {"type": "launchApp", "packageName": "installed.app"}},
        {"code": 240, "rawScanCode": 786593, "long": {"type": "block"}},
      ],
      "appRedirects": [{"sourcePackage": "factory.app", "action": {"type": "openSettings"}}],
    });
    final content = await backup.createBackupContent();
    expect((jsonDecode(content)["apps"][0] as Map).containsKey("icon"), isFalse);
    await mappings.restoreMappings({"keyMappings": [], "rawMappings": [], "appRedirects": []});
    await wallpaper.restoreWallpaper(null);
    await settings.setWeatherUnits(WeatherUnits.si);
    await database.deleteCategory(1);

    expect(await backup.restoreBackupFromContent(content), isEmpty);

    expect(settings.weatherUnits, WeatherUnits.us);
    expect(settings.weatherLatitude, 41);
    expect(wallpaper.bytes, kTransparentImage);
    expect(mappings.keyMappings.single.id, "sc:314");
    expect(mappings.rawMappings.map((m) => m.id), ["240:786597", "240:786593"]);
    expect(mappings.appRedirects.single.sourcePackage, "factory.app");
    expect((await database.select(database.categories).get()).single.name, "Original");
    final app = (await database.getApp("installed.app"))!;
    expect(app.icon, [7]);
    expect(app.sideloaded, isTrue);
    expect(app.isSystemApp, isTrue);
    expect(channel.mappingNotifications, greaterThanOrEqualTo(3));
  });

  test("v1 restores legacy units without replacing existing mappings or wallpaper", () async {
    final data = await snapshot();
    data.remove("buttonMappings");
    data.remove("wallpaper");
    data["version"] = 1;
    data["settings"]["weather"]["units"] = "WeatherUnits.us";
    data["settings"]["weather"]["lat"] = 41;
    await mappings.restoreMappings({"keyMappings": [], "appRedirects": [], "rawMappings": [{"code": 104, "single": {"type": "block"}}]});
    await wallpaper.restoreWallpaper(kTransparentImage);

    await backup.restoreBackupFromContent(jsonEncode(data));

    expect(settings.weatherUnits, WeatherUnits.us);
    expect(settings.weatherLatitude, 41.0);
    expect(mappings.rawMappings.single.code, 104);
    expect(wallpaper.bytes, kTransparentImage);
  });

  test("null settings and wallpaper clear previous values", () async {
    final content = await backup.createBackupContent();
    await settings.setGradientUuid("old");
    await settings.setWeatherLocationName("Old city");
    await settings.setWeatherCoordinates(latitude: 40, longitude: 20);
    await wallpaper.restoreWallpaper(kTransparentImage);

    await backup.restoreBackupFromContent(content);

    expect(settings.gradientUuid, isNull);
    expect(settings.weatherLocationName, isNull);
    expect(settings.weatherLatitude, isNull);
    expect(settings.weatherLongitude, isNull);
    expect(wallpaper.bytes, isNull);
  });

  test("all malformed sections fail before changing layout or settings", () async {
    final original = await snapshot();
    final mutations = <void Function(Map<String, dynamic>)>[
      (d) => d.remove("categories"),
      (d) => d["categories"][0]["sort"] = 20,
      (d) => d["categories"][0]["columnsCount"] = 0,
      (d) => d["categories"][0]["columnsCount"] = 4,
      (d) => d["categories"][0]["rowHeight"] = 81,
      (d) => d["categories"].add(d["categories"][0]),
      (d) => d["apps"][0]["hidden"] = "false",
      (d) => d["appsCategories"][0]["categoryId"] = 999,
      (d) => d["settings"]["weather"]["lat"] = 200,
      (d) => d["buttonMappings"]["rawMappings"] = [{"code": 104, "single": {"type": "launchApp"}}],
      (d) => d["wallpaper"] = "bad base64!",
      (d) => d["wallpaper"] = base64Encode([1, 2, 3]),
      (d) => d["version"] = 99,
    ];
    for (final mutate in mutations) {
      final data = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      data["settings"]["use24HourTimeFormat"] = false;
      mutate(data);
      await expectLater(backup.restoreBackupFromContent(jsonEncode(data)), throwsFormatException);
      expect(settings.use24HourTimeFormat, isTrue);
      expect((await database.select(database.categories).get()).single.name, "Original");
    }
    expect(channel.applicationChecks, 0);
  });

  test("failed mapping notification rolls back database, wallpaper and mappings", () async {
    final data = await snapshot();
    data["categories"][0]["name"] = "Replacement";
    data["wallpaper"] = base64Encode(kTransparentImage);
    data["buttonMappings"]["rawMappings"] = [{"code": 104, "single": {"type": "block"}}];
    channel.failNextNotification = true;

    await expectLater(backup.restoreBackupFromContent(jsonEncode(data)), throwsStateError);

    expect((await database.select(database.categories).get()).single.name, "Original");
    expect(wallpaper.bytes, isNull);
    expect(mappings.rawMappings, isEmpty);
    expect(settings.use24HourTimeFormat, isTrue);
  });

  test("database insert failure keeps preferences and old layout", () async {
    await database.customStatement("CREATE TRIGGER fail_category BEFORE INSERT ON categories WHEN NEW.name = 'Fail' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    final data = await snapshot();
    data["categories"][0]["name"] = "Fail";
    data["settings"]["use24HourTimeFormat"] = false;

    await expectLater(backup.restoreBackupFromContent(jsonEncode(data)), throwsA(anything));

    expect((await database.select(database.categories).get()).single.name, "Original");
    expect(settings.use24HourTimeFormat, isTrue);
  });

  test("missing apps stay hidden and retain category assignments; names never substitute packages", () async {
    final data = await snapshot();
    data["apps"].add({"packageName": "missing.unrelated", "name": "Netflix", "hidden": false});
    data["appsCategories"].add({"categoryId": 1, "appPackageName": "missing.unrelated", "order": 1});

    expect(await backup.restoreBackupFromContent(jsonEncode(data)), isEmpty);

    expect((await database.getApp("missing.unrelated"))!.hidden, isTrue);
    expect((await database.select(database.appsCategories).get()).length, 2);
  });

  test("failed installed-app lookup does not alter data", () async {
    final data = await snapshot();
    data["categories"][0]["name"] = "Replacement";
    channel.failApplicationCheck = true;
    await expectLater(backup.restoreBackupFromContent(jsonEncode(data)), throwsStateError);
    expect((await database.select(database.categories).get()).single.name, "Original");
  });
}

class _BackupChannel extends FLauncherChannel {
  int mappingNotifications = 0, applicationChecks = 0;
  bool failNextNotification = false, failApplicationCheck = false;
  @override
  Future<bool> applicationExists(String packageName) async {
    applicationChecks++;
    if (failApplicationCheck) throw StateError("application lookup failed");
    return packageName == "installed.app";
  }
  @override
  Future<void> notifyButtonMappingsChanged() async {
    mappingNotifications++;
    if (failNextNotification) {
      failNextNotification = false;
      throw StateError("mapping notification failed");
    }
  }
  @override
  Future<bool> isButtonMapperEnabled() async => false;
  @override
  Future<Map<dynamic, dynamic>> rawInputStatus() async => {};
}

class _MemoryWallpaper extends ChangeNotifier implements WallpaperService {
  Uint8List? bytes;
  @override
  Future<Uint8List?> exportWallpaper() async => bytes;
  @override
  Future<void> restoreWallpaper(Uint8List? value) async { bytes = value; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
