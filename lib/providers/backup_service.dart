import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:path_provider/path_provider.dart';

class BackupService {
  final FLauncherDatabase _database;
  final SettingsService _settingsService;
  final FLauncherChannel _channel = FLauncherChannel();

  BackupService(this._database, this._settingsService);

  Future<File> createBackup() async {
    final apps = await _database.select(_database.apps).get();
    final categories = await _database.select(_database.categories).get();
    final appsCategories = await _database.select(_database.appsCategories).get();

    final backupData = {
      "version": 1,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "settings": {
        "use24HourTimeFormat": _settingsService.use24HourTimeFormat,
        "appHighlightAnimationEnabled": _settingsService.appHighlightAnimationEnabled,
        "gradientUuid": _settingsService.gradientUuid,
        "weather": {
          "enabled": _settingsService.weatherEnabled,
          "lat": _settingsService.weatherLatitude,
          "lon": _settingsService.weatherLongitude,
          "locationName": _settingsService.weatherLocationName,
          "showDetails": _settingsService.weatherShowDetails,
          "showCity": _settingsService.weatherShowCity,
          "units": _settingsService.weatherUnits.toString(),
          "refreshInterval": _settingsService.weatherRefreshIntervalMinutes,
        }
      },
      "categories": categories.map((c) => {
        "id": c.id,
        "name": c.name,
        "sort": c.sort.index,
        "type": c.type.index,
        "rowHeight": c.rowHeight,
        "columnsCount": c.columnsCount,
        "order": c.order,
      }).toList(),
      "appsCategories": appsCategories.map((ac) => {
        "categoryId": ac.categoryId,
        "appPackageName": ac.appPackageName,
        "order": ac.order,
      }).toList(),
      "apps": apps.map((a) => {
        "packageName": a.packageName,
        "name": a.name,
        "hidden": a.hidden,
        "sideloaded": a.sideloaded,
        "isSystemApp": a.isSystemApp,
      }).toList(),
    };

    final jsonString = jsonEncode(backupData);

    Directory? directory;
    if (Platform.isAndroid) {
      final externalDir = Directory("/storage/emulated/0/Download");
      if (await externalDir.exists()) {
         directory = externalDir;
      }
    }
    
    if (directory == null) {
      directory = await getApplicationDocumentsDirectory();
    }

    final file = File('${directory.path}/flauncher_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonString);
    return file;
  }
  
  Future<void> shareBackup(File file) async {
    await _channel.shareFile(file.path);
  }

  Future<List<AppSpec>> restoreBackup(File file) async {
    final content = await file.readAsString();
    final data = jsonDecode(content);

    if (data["version"] != 1) {
      throw Exception("Unsupported backup version");
    }

    if (data.containsKey("settings") && data["settings"] != null) {
      await _settingsService.restoreSettings(data["settings"] as Map<String, dynamic>);
    }
    
    await _database.transaction(() async {
      await _database.delete(_database.appsCategories).go();
      await _database.delete(_database.categories).go();
      
      final categoriesList = data["categories"] as List?;
      if (categoriesList != null) {
        final categoriesData = categoriesList.cast<Map<String, dynamic>>();
        for (var c in categoriesData) {
          await _database.into(_database.categories).insert(
            CategoriesCompanion(
              id: drift.Value(c["id"]),
              name: drift.Value(c["name"] ?? "Category"),
              sort: drift.Value(CategorySort.values[c["sort"] ?? 0]),
              type: drift.Value(CategoryType.values[c["type"] ?? 0]),
              rowHeight: drift.Value(c["rowHeight"] ?? 110),
              columnsCount: drift.Value(c["columnsCount"] ?? 6),
              order: drift.Value(c["order"] ?? 0),
            ),
            mode: drift.InsertMode.insertOrReplace
          );
        }
      }

      final appsCategoriesList = data["appsCategories"] as List?;
      if (appsCategoriesList != null) {
        final appsCategoriesData = appsCategoriesList.cast<Map<String, dynamic>>();
        for (var ac in appsCategoriesData) {
          await _database.into(_database.appsCategories).insert(
            AppsCategoriesCompanion(
              categoryId: drift.Value(ac["categoryId"]),
              appPackageName: drift.Value(ac["appPackageName"]),
              order: drift.Value(ac["order"] ?? 0),
            ),
            mode: drift.InsertMode.insertOrReplace
          );
        }
      }
      
      final appsList = data["apps"] as List?;
      if (appsList != null) {
        final appsData = appsList.cast<Map<String, dynamic>>();
        for (var a in appsData) {
          final packageName = a["packageName"];
          if (packageName == null) continue;

          final existing = await (_database.select(_database.apps)..where((tbl) => tbl.packageName.equals(packageName))).getSingleOrNull();
          
          if (existing != null) {
             await (_database.update(_database.apps)..where((tbl) => tbl.packageName.equals(packageName))).write(
               AppsCompanion(
                 hidden: drift.Value(a["hidden"] ?? false),
                 sideloaded: drift.Value(a["sideloaded"] ?? false),
                 isSystemApp: drift.Value(a["isSystemApp"] ?? false),
               )
             );
          } else {
            await _database.into(_database.apps).insert(
              AppsCompanion(
                packageName: drift.Value(packageName),
                name: drift.Value(a["name"] ?? ""),
                version: drift.Value(""),
                hidden: drift.Value(a["hidden"] ?? false),
                sideloaded: drift.Value(a["sideloaded"] ?? false),
                isSystemApp: drift.Value(a["isSystemApp"] ?? false),
              )
            );
          }
        }
      }
    });

    final appsList = data["apps"] as List?;
    final missingApps = <AppSpec>[];
    
    if (appsList != null) {
      final appsData = appsList.cast<Map<String, dynamic>>();
      for (var a in appsData) {
        final packageName = a["packageName"];
        if (packageName == null) continue;

        final exists = await _channel.applicationExists(packageName);
        if (!exists) {
          final known = AppInstallService.knownApps.firstWhere(
            (spec) => spec.packageName == packageName,
            orElse: () => AppSpec(name: a["name"] ?? "Unknown", packageName: packageName, sources: [])
          );
          if (known.sources.isNotEmpty) {
             missingApps.add(known);
          }
        }
      }
    }
    
    return missingApps;
  }
}
