/*
 * FLaunchermod
 * Copyright (C)
 * 2026 - ctnkyaumt
 * Forked from: 2021  Étienne Fesser
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

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';

const _flauncherPackageName = "me.efesser.flauncher";
const _tvCategoryName = "TV Applications";
const _nonTvCategoryName = "Non-TV Applications";

class AppsService extends ChangeNotifier {
  final FLauncherChannel _fLauncherChannel;
  final FLauncherDatabase _database;
  bool _initialized = false;
  final StreamController<String> _packageAddedController = StreamController<String>.broadcast();

  /// Expose the FLauncherChannel to allow access to platform-specific functionality
  FLauncherChannel get fLauncherChannel => _fLauncherChannel;
  Stream<String> get packageAddedStream => _packageAddedController.stream;

  List<App> _applications = [];
  List<CategoryWithApps> _categoriesWithApps = [];

  /// Cached read-only view of [_categoriesWithApps], rebuilt only when the
  /// underlying state changes. The getter is hit on every widget rebuild, so
  /// re-wrapping every category on each access is wasteful.
  List<CategoryWithApps>? _categoriesWithAppsView;

  bool get initialized => _initialized;

  List<App> get applications => UnmodifiableListView(_applications);

  List<CategoryWithApps> get categoriesWithApps => _categoriesWithAppsView ??= _categoriesWithApps
      .map((item) => CategoryWithApps(item.category, UnmodifiableListView(item.applications)))
      .toList(growable: false);

  set _categories(List<CategoryWithApps> value) {
    _categoriesWithApps = value;
    _categoriesWithAppsView = null;
  }

  AppsService(this._fLauncherChannel, this._database) {
    _init();
  }

  @override
  void dispose() {
    _packageAddedController.close();
    super.dispose();
  }

  Future<void> _init() async {
    await _refreshState(shouldNotifyListeners: false);
    if (_database.wasCreated) {
      await _initDefaultCategories();
    }
    await _ensureTvApplicationsTop(shouldNotifyListeners: false);
    _fLauncherChannel.addAppsChangedListener(_onAppsChanged);
    _initialized = true;
    notifyListeners();
  }

  Future<void> _onAppsChanged(Map<dynamic, dynamic> event) async {
    switch (event["action"]) {
      case "PACKAGE_ADDED":
      case "PACKAGE_CHANGED":
        final appInfo = event["activitiyInfo"];
        final packageName = appInfo["packageName"] as String?;
        if (packageName != null) {
          _packageAddedController.add(packageName);
        }
        await _database.persistApps([_buildAppCompanion(appInfo)]);
        await _autoAssignToDefaultCategories([appInfo]);
        break;
      case "PACKAGES_AVAILABLE":
        final appsInfo = (event["activitiesInfo"] as List<dynamic>);
        await _database.persistApps(appsInfo.map(_buildAppCompanion).toList());
        await _autoAssignToDefaultCategories(appsInfo);
        break;
      case "PACKAGE_REMOVED":
        await _database.deleteApps([event["packageName"]]);
        break;
    }
    _categories = await _database.listCategoriesWithVisibleApps();
    _applications = await _database.listApplications();
    await _ensureTvApplicationsTop(shouldNotifyListeners: false);
    notifyListeners();
  }

  /// Files newly seen, user-visible apps into their default category, creating
  /// that category if it does not exist yet.
  ///
  /// Assignments are grouped per target category and inserted in a single batch,
  /// so the (expensive, blob-loading) category listing is refreshed at most twice
  /// instead of once per application.
  Future<void> _autoAssignToDefaultCategories(List<dynamic> appsInfo) async {
    final packageNamesByCategory = <String, List<String>>{};
    for (final appInfo in appsInfo) {
      if (appInfo["isSystemApp"] == true) {
        continue;
      }
      final packageName = appInfo["packageName"]?.toString();
      if (packageName == null || packageName == _flauncherPackageName) {
        continue;
      }
      if (await _database.isAppInAnyCategory(packageName)) {
        continue;
      }
      final targetCategoryName = appInfo["sideloaded"] == true ? _nonTvCategoryName : _tvCategoryName;
      packageNamesByCategory.putIfAbsent(targetCategoryName, () => []).add(packageName);
    }

    if (packageNamesByCategory.isEmpty) {
      return;
    }

    _categories = await _database.listCategoriesWithVisibleApps();
    for (final entry in packageNamesByCategory.entries) {
      final category = await _findOrCreateCategory(entry.key);
      await _insertIntoCategory(category, entry.value);
    }
  }

  Future<Category> _findOrCreateCategory(String name) async {
    final existing = _categoriesWithApps.map((e) => e.category).firstWhereOrNull((c) => c.name == name);
    if (existing != null) {
      return existing;
    }
    await addCategory(name, shouldNotifyListeners: false);
    return _categoriesWithApps.map((e) => e.category).firstWhere((c) => c.name == name);
  }

  /// Appends [packageNames] to [category] in a single batch, without refreshing
  /// the in-memory state. Callers are responsible for refreshing when needed.
  Future<void> _insertIntoCategory(Category category, List<String> packageNames) async {
    if (packageNames.isEmpty) {
      return;
    }
    var order = await _database.nextAppCategoryOrder(category.id) ?? 0;
    await _database.insertAppsCategories([
      for (final packageName in packageNames)
        AppsCategoriesCompanion.insert(
          categoryId: category.id,
          appPackageName: packageName,
          order: order++,
        )
    ]);
  }

  AppsCompanion _buildAppCompanion(dynamic data) => AppsCompanion(
        packageName: Value(data["packageName"]),
        name: Value(data["name"]),
        version: Value(data["version"] ?? "(unknown)"),
        banner: Value(data["banner"]),
        icon: Value(data["icon"]),
        hidden: Value((data["isSystemApp"] ?? false) || data["packageName"] == "me.efesser.flauncher"),
        sideloaded: Value(data["sideloaded"]),
        isSystemApp: Value(data["isSystemApp"] ?? false),
      );

  AppsCompanion _buildAppCompanionPreservingHidden(dynamic data, {required bool? existingHidden}) => AppsCompanion(
        packageName: Value(data["packageName"]),
        name: Value(data["name"]),
        version: Value(data["version"] ?? "(unknown)"),
        banner: Value(data["banner"]),
        icon: Value(data["icon"]),
        hidden: Value(existingHidden ?? ((data["isSystemApp"] ?? false) || data["packageName"] == "me.efesser.flauncher")),
        sideloaded: Value(data["sideloaded"]),
        isSystemApp: Value(data["isSystemApp"] ?? false),
      );

  Future<void> _initDefaultCategories() => _database.transaction(() async {
        final tvApplications = _applications.where((app) => !app.sideloaded).toList(growable: false);
        final nonTvApplications = _applications.where((app) => app.sideloaded).toList(growable: false);
        if (nonTvApplications.isNotEmpty) {
          await addCategory(_nonTvCategoryName, shouldNotifyListeners: false);
          final nonTvAppsCategory =
              _categoriesWithApps.map((e) => e.category).firstWhere((element) => element.name == _nonTvCategoryName);
          await _insertIntoCategory(nonTvAppsCategory, nonTvApplications.map((app) => app.packageName).toList());
        }
        if (tvApplications.isNotEmpty) {
          await addCategory(_tvCategoryName, shouldNotifyListeners: false);
          final tvAppsCategory =
              _categoriesWithApps.map((e) => e.category).firstWhere((element) => element.name == _tvCategoryName);
          await _database.updateCategory(tvAppsCategory.id, CategoriesCompanion(type: Value(CategoryType.row)));
          await _insertIntoCategory(tvAppsCategory, tvApplications.map((app) => app.packageName).toList());
        }
        _categories = await _database.listCategoriesWithVisibleApps();
      });

  /// Keeps the "TV Applications" category pinned first and rendered as a row.
  ///
  /// Runs after every package event, so it must avoid writing when nothing
  /// changed: redundant writes force an extra full re-read of every app blob.
  Future<void> _ensureTvApplicationsTop({bool shouldNotifyListeners = true}) async {
    await _database.transaction(() async {
      final categoriesWithApps = await _database.listCategoriesWithVisibleApps();
      final categories = categoriesWithApps.map((e) => e.category).toList();
      final tvIndex = categories.indexWhere((c) => c.name == _tvCategoryName);
      if (tvIndex == -1) {
        _categories = categoriesWithApps;
        return;
      }

      final tvCategory = categories.removeAt(tvIndex);
      categories.insert(0, tvCategory);

      final needsTypeChange = tvCategory.type != CategoryType.row;
      final needsReorder = tvIndex != 0;
      if (!needsTypeChange && !needsReorder) {
        _categories = categoriesWithApps;
        return;
      }

      if (needsTypeChange) {
        await _database.updateCategory(tvCategory.id, CategoriesCompanion(type: Value(CategoryType.row)));
      }
      if (needsReorder) {
        await _database.updateCategories([
          for (int i = 0; i < categories.length; i++)
            CategoriesCompanion(id: Value(categories[i].id), order: Value(i))
        ]);
      }
      _categories = await _database.listCategoriesWithVisibleApps();
    });
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> _refreshState({bool shouldNotifyListeners = true}) async {
    await _database.transaction(() async {
      final existingApps = await _database.listApplications();
      final existingAppsByPackageName = <String, App>{
        for (final app in existingApps) app.packageName: app,
      };

      final appsFromSystem = (await _fLauncherChannel.getApplications())
          .map((data) => _buildAppCompanionPreservingHidden(
                data,
                existingHidden: existingAppsByPackageName[data["packageName"]]?.hidden,
              ))
          .toList();

      final packageNamesFromSystem = appsFromSystem.map((app) => app.packageName.value).toSet();
      final appsRemovedFromSystem = existingApps
          .map((app) => app.packageName)
          .where((packageName) => !packageNamesFromSystem.contains(packageName));

      final uninstalledApplications = <String>[];
      for (final packageName in appsRemovedFromSystem) {
        if (!(await _fLauncherChannel.applicationExists(packageName))) {
          uninstalledApplications.add(packageName);
        }
      }

      await _database.persistApps(appsFromSystem);
      await _database.deleteApps(uninstalledApplications);

      _categories = await _database.listCategoriesWithVisibleApps();
      _applications = await _database.listApplications();
    });
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> launchApp(App app) => _fLauncherChannel.launchApp(app.packageName);

  Future<void> openAppInfo(App app) => _fLauncherChannel.openAppInfo(app.packageName);

  Future<void> uninstallApp(App app) => _fLauncherChannel.uninstallApp(app.packageName);

  Future<void> openSettings() => _fLauncherChannel.openSettings();

  Future<void> openWifiSettings() => _fLauncherChannel.openWifiSettings();

  Future<bool> isDefaultLauncher() => _fLauncherChannel.isDefaultLauncher();

  Future<void> startAmbientMode() => _fLauncherChannel.startAmbientMode();

  Future<void> addToCategory(App app, Category category, {bool shouldNotifyListeners = true}) async {
    await _insertIntoCategory(category, [app.packageName]);
    _categories = await _database.listCategoriesWithVisibleApps();
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> removeFromCategory(App app, Category category) async {
    await _database.deleteAppCategory(category.id, app.packageName);
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  Future<void> saveOrderInCategory(Category category) async {
    final applications = _categoriesWithApps.firstWhere((element) => element.category.id == category.id).applications;
    final orderedAppCategories = <AppsCategoriesCompanion>[];
    for (int i = 0; i < applications.length; ++i) {
      orderedAppCategories.add(AppsCategoriesCompanion(
        categoryId: Value(category.id),
        appPackageName: Value(applications[i].packageName),
        order: Value(i),
      ));
    }
    await _database.replaceAppsCategories(orderedAppCategories);
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  void reorderApplication(Category category, int oldIndex, int newIndex) {
    final applications = _categoriesWithApps.firstWhere((element) => element.category.id == category.id).applications;
    final application = applications.removeAt(oldIndex);
    applications.insert(newIndex, application);
    notifyListeners();
  }

  Future<void> addCategory(String categoryName, {bool shouldNotifyListeners = true}) async {
    final orderedCategories = <CategoriesCompanion>[];
    for (int i = 0; i < _categoriesWithApps.length; ++i) {
      final category = _categoriesWithApps[i].category;
      orderedCategories.add(CategoriesCompanion(id: Value(category.id), order: Value(i + 1)));
    }
    await _database.insertCategory(CategoriesCompanion.insert(name: categoryName, order: 0));
    await _database.updateCategories(orderedCategories);
    _categories = await _database.listCategoriesWithVisibleApps();
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> renameCategory(Category category, String categoryName) async {
    await _database.updateCategory(category.id, CategoriesCompanion(name: Value(categoryName)));
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  Future<void> deleteCategory(Category category) async {
    await _database.deleteCategory(category.id);
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  Future<void> moveCategory(int oldIndex, int newIndex) async {
    final categoryWithApps = _categoriesWithApps.removeAt(oldIndex);
    _categoriesWithApps.insert(newIndex, categoryWithApps);
    _categoriesWithAppsView = null;
    final orderedCategories = <CategoriesCompanion>[];
    for (int i = 0; i < _categoriesWithApps.length; ++i) {
      final category = _categoriesWithApps[i].category;
      orderedCategories.add(CategoriesCompanion(id: Value(category.id), order: Value(i)));
    }
    await _database.updateCategories(orderedCategories);
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  Future<void> hideApplication(App application) async {
    await _database.updateApp(application.packageName, AppsCompanion(hidden: Value(true)));
    _categories = await _database.listCategoriesWithVisibleApps();
    _applications = await _database.listApplications();
    notifyListeners();
  }

  Future<void> unHideApplication(App application) async {
    await _database.updateApp(application.packageName, AppsCompanion(hidden: Value(false)));
    _categories = await _database.listCategoriesWithVisibleApps();
    _applications = await _database.listApplications();
    notifyListeners();
  }

  Future<void> setCategoryType(Category category, CategoryType type, {bool shouldNotifyListeners = true}) async {
    await _database.updateCategory(category.id, CategoriesCompanion(type: Value(type)));
    _categories = await _database.listCategoriesWithVisibleApps();
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> setCategorySort(Category category, CategorySort sort) async {
    await _database.updateCategory(category.id, CategoriesCompanion(sort: Value(sort)));
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  Future<void> setCategoryColumnsCount(Category category, int columnsCount) async {
    await _database.updateCategory(category.id, CategoriesCompanion(columnsCount: Value(columnsCount)));
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  Future<void> setCategoryRowHeight(Category category, int rowHeight) async {
    await _database.updateCategory(category.id, CategoriesCompanion(rowHeight: Value(rowHeight)));
    _categories = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }
}
