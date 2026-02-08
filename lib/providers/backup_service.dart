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
      // On Android 11+ (API 30+), we can't easily write to /storage/emulated/0/Download 
      // directly without special permissions or SAF.
      // However, for Android TV and general compatibility, we try the standard public downloads.
      // If that fails or is restricted, we fallback to app-specific external files which are physical.
      try {
        final externalDir = Directory("/storage/emulated/0/Download");
        if (await externalDir.exists()) {
           // Check if we can actually write there
           final testFile = File("${externalDir.path}/.test_write");
           await testFile.writeAsString("test");
           await testFile.delete();
           directory = externalDir;
        }
      } catch (e) {
        // Fallback to media/downloads via path_provider or app external storage
      }
    }
    
    if (directory == null) {
      // Use getExternalStorageDirectory for physical files on Android that the user can see via file manager
      // usually in Android/data/me.efesser.flauncher/files
      final external = await getExternalStorageDirectory();
      if (external != null) {
        directory = external;
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/flauncher_backup_$timestamp.json');
    await file.writeAsString(jsonString);
    return file;
  }
  
  Future<void> shareBackup(File file) async {
    await _channel.shareFile(file.path);
  }

  Future<List<AppSpec>> restoreBackup(File file) async {
    final String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      throw Exception("Failed to read backup file: $e");
    }

    final dynamic data;
    try {
      data = jsonDecode(content);
    } catch (e) {
      throw Exception("Failed to parse backup JSON: $e");
    }

    if (data is! Map<String, dynamic>) {
      throw Exception("Invalid backup format: root must be an object");
    }

    if (data["version"] != 1) {
      throw Exception("Unsupported backup version: ${data["version"]}");
    }

    if (data.containsKey("settings") && data["settings"] != null) {
      await _settingsService.restoreSettings(data["settings"] as Map<String, dynamic>);
    }
    
    await _database.transaction(() async {
      await _database.delete(_database.appsCategories).go();
      await _database.delete(_database.categories).go();
      
      final categoriesList = data["categories"];
      if (categoriesList is List) {
        for (var c in categoriesList) {
          if (c is! Map<String, dynamic>) continue;
          final id = c["id"];
          if (id is! int) continue;

          await _database.into(_database.categories).insert(
            CategoriesCompanion(
              id: drift.Value(id),
              name: drift.Value(c["name"]?.toString() ?? "Category"),
              sort: drift.Value(CategorySort.values[(c["sort"] as int?) ?? 0]),
              type: drift.Value(CategoryType.values[(c["type"] as int?) ?? 0]),
              rowHeight: drift.Value((c["rowHeight"] as int?) ?? 110),
              columnsCount: drift.Value((c["columnsCount"] as int?) ?? 6),
              order: drift.Value((c["order"] as int?) ?? 0),
            ),
            mode: drift.InsertMode.insertOrReplace
          );
        }
      }

      final appsCategoriesList = data["appsCategories"];
      if (appsCategoriesList is List) {
        for (var ac in appsCategoriesList) {
          if (ac is! Map<String, dynamic>) continue;
          final catId = ac["categoryId"];
          final pkg = ac["appPackageName"];
          if (catId is! int || pkg is! String) continue;

          await _database.into(_database.appsCategories).insert(
            AppsCategoriesCompanion(
              categoryId: drift.Value(catId),
              appPackageName: drift.Value(pkg),
              order: drift.Value((ac["order"] as int?) ?? 0),
            ),
            mode: drift.InsertMode.insertOrReplace
          );
        }
      }
      
      final appsList = data["apps"];
      if (appsList is List) {
        for (var a in appsList) {
          if (a is! Map<String, dynamic>) continue;
          final packageName = a["packageName"]?.toString();
          if (packageName == null || packageName.isEmpty) continue;

          final existing = await (_database.select(_database.apps)..where((tbl) => tbl.packageName.equals(packageName))).getSingleOrNull();
          
          if (existing != null) {
             await (_database.update(_database.apps)..where((tbl) => tbl.packageName.equals(packageName))).write(
               AppsCompanion(
                 hidden: drift.Value((a["hidden"] as bool?) ?? false),
                 sideloaded: drift.Value((a["sideloaded"] as bool?) ?? false),
                 isSystemApp: drift.Value((a["isSystemApp"] as bool?) ?? false),
               )
             );
          } else {
            await _database.into(_database.apps).insert(
              AppsCompanion(
                packageName: drift.Value(packageName),
                name: drift.Value(a["name"]?.toString() ?? ""),
                version: drift.Value(""),
                hidden: drift.Value((a["hidden"] as bool?) ?? false),
                sideloaded: drift.Value((a["sideloaded"] as bool?) ?? false),
                isSystemApp: drift.Value((a["isSystemApp"] as bool?) ?? false),
              )
            );
          }
        }
      }
    });

    final appsList = data["apps"];
    final missingApps = <AppSpec>[];
    
    if (appsList is List) {
      for (var a in appsList) {
        if (a is! Map<String, dynamic>) continue;
        final packageName = a["packageName"]?.toString();
        if (packageName == null || packageName.isEmpty) continue;

        final exists = await _channel.applicationExists(packageName);
        if (!exists) {
          final known = AppInstallService.knownApps.firstWhere(
            (spec) => spec.packageName == packageName,
            orElse: () => AppSpec(name: a["name"]?.toString() ?? "Unknown", packageName: packageName, sources: [])
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
