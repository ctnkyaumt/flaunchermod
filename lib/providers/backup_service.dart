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
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' as drift;
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BackupService {
  static const maxBackupBytes = 32 * 1024 * 1024;
  final FLauncherDatabase _database;
  final SettingsService _settingsService;
  final ButtonMappingService _buttonMappings;
  final WallpaperService _wallpaper;
  final FLauncherChannel _channel;

  BackupService(this._database, this._settingsService, {
    required ButtonMappingService buttonMappings,
    required WallpaperService wallpaper,
    FLauncherChannel? channel,
  }) : _buttonMappings = buttonMappings,
       _wallpaper = wallpaper,
       _channel = channel ?? FLauncherChannel();

  Future<String> createBackupContent() async {
    final wallpaper = await _wallpaper.exportWallpaper();
    final data = await _database.transaction(() async {
      // Metadata only: installed apps supply their icons and banners on restore.
      final query = _database.selectOnly(_database.apps)..addColumns([
        _database.apps.packageName, _database.apps.name, _database.apps.hidden,
        _database.apps.sideloaded, _database.apps.isSystemApp,
      ]);
      final apps = await query.get();
      final categories = await _database.select(_database.categories).get();
      final assignments = await _database.select(_database.appsCategories).get();
      return <String, dynamic>{
        "version": 2,
        "timestamp": DateTime.now().millisecondsSinceEpoch,
        "settings": _settingsService.exportSettings(),
        "buttonMappings": _buttonMappings.exportMappings(),
        "wallpaper": wallpaper == null ? null : base64Encode(wallpaper),
        "categories": categories.map((c) => {
          "id": c.id, "name": c.name, "sort": c.sort.index, "type": c.type.index,
          "rowHeight": c.rowHeight, "columnsCount": c.columnsCount, "order": c.order,
        }).toList(),
        "appsCategories": assignments.map((a) => {
          "categoryId": a.categoryId, "appPackageName": a.appPackageName, "order": a.order,
        }).toList(),
        "apps": apps.map((row) => {
          "packageName": row.read(_database.apps.packageName),
          "name": row.read(_database.apps.name),
          "hidden": row.read(_database.apps.hidden),
          "sideloaded": row.read(_database.apps.sideloaded),
          "isSystemApp": row.read(_database.apps.isSystemApp),
        }).toList(),
      };
    });
    final content = jsonEncode(data);
    if (utf8.encode(content).length > maxBackupBytes) {
      throw FormatException("Backup exceeds 32 MiB; choose a smaller wallpaper");
    }
    return content;
  }

  Future<File> createBackup() async {
    final content = await createBackupContent();
    final directory = await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    final file = File('${directory.path}/flauncher_backup_${DateTime.now().microsecondsSinceEpoch}.json');
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(content, flush: true);
      return await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<String> saveBackup() async {
    final file = await createBackup();
    if (Platform.isAndroid) {
      try {
        final location = await _channel.saveBackupToDownloads(file.path);
        if (location != null) {
          await file.delete();
          return location;
        }
      } catch (error) {
        debugPrint("Backup Downloads export failed: $error");
      }
    }
    return file.path;
  }

  Future<void> shareBackup(File file) async { await _channel.shareFile(file.path); }

  Future<List<AppSpec>> restoreBackup(File file) async {
    if (await file.length() > maxBackupBytes) throw FormatException("Backup exceeds 32 MiB");
    return restoreBackupFromContent(await file.readAsString());
  }

  static Map<String, dynamic> _validate(String content) {
    if (content.length > maxBackupBytes || utf8.encode(content).length > maxBackupBytes) {
      throw FormatException("Backup exceeds 32 MiB");
    }
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic>) throw FormatException("Backup must be an object");
    if (data["version"] is! int || (data["version"] != 1 && data["version"] != 2)) {
      throw FormatException("Unsupported backup version");
    }
    Map<String, dynamic> object(dynamic value) {
      if (value is! Map<String, dynamic>) throw FormatException("Invalid backup entry");
      return value;
    }
    List<Map<String, dynamic>> entries(String key) {
      final value = data[key];
      if (value is! List) throw FormatException("Missing backup list: $key");
      return value.map(object).toList();
    }
    void field(Map<String, dynamic> row, String key, bool Function(dynamic) valid) {
      if (!valid(row[key])) throw FormatException("Invalid backup field: $key");
    }
    bool text(dynamic value) => value is String && value.isNotEmpty;
    bool nullableText(dynamic value) => value == null || value is String;
    bool integer(dynamic value) => value is int && value >= 0;
    final packages = <String>{};
    for (final app in entries("apps")) {
      field(app, "packageName", text);
      if (!packages.add(app["packageName"] as String)) throw FormatException("Duplicate app");
      if (app.containsKey("name")) field(app, "name", (v) => v is String);
      for (final key in ["hidden", "sideloaded", "isSystemApp"]) {
        if (app.containsKey(key)) field(app, key, (v) => v is bool);
      }
    }
    final categories = <int>{};
    for (final category in entries("categories")) {
      field(category, "id", integer);
      if (!categories.add(category["id"] as int)) throw FormatException("Duplicate category");
      field(category, "name", text);
      for (final key in ["sort", "type"]) {
        if (category.containsKey(key)) field(category, key, (v) => v is int && v >= 0 && v < 2);
      }
      if (category.containsKey("rowHeight")) field(category, "rowHeight", (v) =>
          v is int && v >= 80 && v <= 150 && v % 10 == 0);
      if (category.containsKey("columnsCount")) field(category, "columnsCount", (v) =>
          v is int && v >= 5 && v <= 10);
      if (category.containsKey("order")) field(category, "order", integer);
    }
    final assignments = <String>{};
    for (final assignment in entries("appsCategories")) {
      field(assignment, "categoryId", (v) => v is int && categories.contains(v));
      field(assignment, "appPackageName", (v) => v is String && packages.contains(v));
      if (assignment.containsKey("order")) field(assignment, "order", integer);
      if (!assignments.add('${assignment["categoryId"]}:${assignment["appPackageName"]}')) {
        throw FormatException("Duplicate app assignment");
      }
    }
    final settings = object(data["settings"]);
    for (final key in ["use24HourTimeFormat", "appHighlightAnimationEnabled"]) {
      if (settings.containsKey(key)) field(settings, key, (v) => v is bool);
    }
    for (final key in ["gradientUuid", "unsplashAuthor"]) {
      if (settings.containsKey(key)) field(settings, key, nullableText);
    }
    if (settings.containsKey("weather")) {
      final weather = object(settings["weather"]);
      for (final key in ["enabled", "showDetails", "showCity"]) {
        if (weather.containsKey(key)) field(weather, key, (v) => v is bool);
      }
      for (final key in ["lat", "lon"]) {
        final limit = key == "lat" ? 90 : 180;
        if (weather.containsKey(key)) field(weather, key, (v) =>
            v == null || (v is num && v.isFinite && v.abs() <= limit));
      }
      if (weather.containsKey("locationName")) field(weather, "locationName", nullableText);
      if (weather.containsKey("units")) field(weather, "units", (v) =>
          ["us", "si", "WeatherUnits.us", "WeatherUnits.si"].contains(v));
      if (weather.containsKey("refreshInterval")) field(weather, "refreshInterval", (v) => v is int);
    }
    if (data["version"] == 2) {
      ButtonMappingService.validateBackupMappings(object(data["buttonMappings"]));
      if (!data.containsKey("wallpaper")) throw FormatException("Missing wallpaper");
      field(data, "wallpaper", nullableText);
      if (data["wallpaper"] != null) {
        final bytes = base64Decode(data["wallpaper"] as String);
        if (bytes.isEmpty) throw FormatException("Empty wallpaper");
      }
    }
    return data;
  }

  Future<List<AppSpec>> restoreBackupFromContent(String content) async {
    // Validate every section before making any persistent changes.
    final data = _validate(content);
    if (data["version"] == 2 && data["wallpaper"] != null) {
      try {
        final codec = await ui.instantiateImageCodec(base64Decode(data["wallpaper"] as String));
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } catch (_) {
        throw FormatException("Invalid wallpaper image");
      }
    }
    final apps = (data["apps"] as List).cast<Map<String, dynamic>>();
    final installed = <String, bool>{};
    final missingApps = <AppSpec>[];
    for (final app in apps) {
      final package = app["packageName"] as String;
      final exists = await _channel.applicationExists(package).timeout(Duration(seconds: 5));
      installed[package] = exists;
      if (!exists) {
        for (final known in AppInstallService.knownApps) {
          if (known.packageName == package && known.sources.isNotEmpty) {
            missingApps.add(known);
            break;
          }
        }
      }
    }
    final settingsBefore = _settingsService.exportSettings();
    final mappingsBefore = _buttonMappings.exportMappings();
    final wallpaperBefore = await _wallpaper.exportWallpaper();
    final version2 = data["version"] == 2;
    bool settingsStarted = false, mappingsStarted = false, wallpaperStarted = false;
    try {
      await _database.transaction(() async {
        await _database.delete(_database.appsCategories).go();
        await _database.delete(_database.categories).go();
        final query = _database.selectOnly(_database.apps)..addColumns([_database.apps.packageName]);
        final existing = (await query.get()).map((row) => row.read(_database.apps.packageName)!).toSet();
        for (final app in apps) {
          final package = app["packageName"] as String;
          final hidden = (app["hidden"] as bool? ?? false) || !installed[package]!;
          if (existing.contains(package)) {
            // Installation metadata comes from this TV, not the source TV.
            await _database.updateApp(package, AppsCompanion(hidden: drift.Value(hidden)));
          } else {
            await _database.into(_database.apps).insert(AppsCompanion.insert(
              packageName: package, name: app["name"] as String? ?? package, version: "",
              hidden: drift.Value(hidden), sideloaded: drift.Value(app["sideloaded"] as bool? ?? false),
              isSystemApp: drift.Value(app["isSystemApp"] as bool? ?? false),
            ));
          }
        }
        for (final c in (data["categories"] as List).cast<Map<String, dynamic>>()) {
          await _database.into(_database.categories).insert(CategoriesCompanion.insert(
            id: drift.Value(c["id"] as int), name: c["name"] as String,
            sort: drift.Value(CategorySort.values[c["sort"] as int? ?? 0]),
            type: drift.Value(CategoryType.values[c["type"] as int? ?? 0]),
            rowHeight: drift.Value(c["rowHeight"] as int? ?? 110),
            columnsCount: drift.Value(c["columnsCount"] as int? ?? 6), order: c["order"] as int? ?? 0,
          ));
        }
        await _database.insertAppsCategories((data["appsCategories"] as List).map((a) =>
            AppsCategoriesCompanion.insert(categoryId: a["categoryId"] as int,
              appPackageName: a["appPackageName"] as String, order: a["order"] as int? ?? 0)).toList());
        if (version2) {
          wallpaperStarted = true;
          await _wallpaper.restoreWallpaper(data["wallpaper"] == null
              ? null : base64Decode(data["wallpaper"] as String));
          mappingsStarted = true;
          await _buttonMappings.restoreMappings(data["buttonMappings"] as Map<String, dynamic>);
        }
        settingsStarted = true;
        await _settingsService.restoreSettings(data["settings"] as Map<String, dynamic>);
      });
    } catch (error) {
      // SQLite rolls back its transaction; compensate the other stores as well.
      final failedRollbacks = <String>[];
      Future<void> rollback(String store, Future<void> Function() restore) async {
        try {
          await restore();
        } catch (rollbackError) {
          failedRollbacks.add(store);
          debugPrint("Backup rollback failed for $store: $rollbackError");
        }
      }
      if (settingsStarted) await rollback("settings", () => _settingsService.restoreSettings(settingsBefore));
      if (mappingsStarted) await rollback("mappings", () => _buttonMappings.restoreMappings(mappingsBefore));
      if (wallpaperStarted) await rollback("wallpaper", () => _wallpaper.restoreWallpaper(wallpaperBefore));
      if (failedRollbacks.isNotEmpty) {
        throw StateError("Restore failed: $error; recovery failed for ${failedRollbacks.join(', ')}");
      }
      rethrow;
    }
    return missingApps;
  }
}
