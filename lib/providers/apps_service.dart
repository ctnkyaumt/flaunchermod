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

import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/default_categories.dart';
import 'package:flauncher/providers/restored_apps.dart';
import 'package:flutter/foundation.dart' hide Category;

/// The apps and categories shown on the home screen.
///
/// Every change (package event, user edit, refresh after a restore) goes
/// through one queue: changes are written to the database one at a time, in
/// arrival order, and the shown state is reloaded and listeners notified once
/// when the queue drains. A public method's Future completes once its change
/// is written and the shown state reflects it.
class AppsService extends ChangeNotifier {
  final FLauncherChannel _fLauncherChannel;
  final FLauncherDatabase _database;
  final DefaultCategories _defaultCategories;
  bool _initialized = false;
  bool _disposed = false;
  final StreamController<String> _packageAddedController = StreamController<String>.broadcast();

  final Queue<_PendingChange> _pendingChanges = Queue<_PendingChange>();
  bool _applyingChanges = false;

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

  AppsService(this._fLauncherChannel, this._database) : _defaultCategories = DefaultCategories(_database) {
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    _packageAddedController.close();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await _apply(() async {
        await _syncWithSystem();
        if (_database.wasCreated) {
          await _defaultCategories.createInitialCategories(await _database.listApplications());
        }
        await _defaultCategories.pinTvApplicationsFirst();
      }, appsChanged: true);
    } catch (e) {
      // The reload after the failed change still shows the saved layout,
      // which is better than "Loading..." forever.
      debugPrint('AppsService: initial load failed - $e');
    }
    if (_disposed) {
      return;
    }
    _fLauncherChannel.addPackageEventListener(_onAppsChanged);
    _initialized = true;
    notifyListeners();
  }

  /// Queues [change] (database writes only) and completes once it is written
  /// and the shown state has been reloaded, with [change]'s error if it failed.
  Future<void> _apply(Future<void> Function() change, {bool appsChanged = false, bool notify = true}) {
    final pending = _PendingChange(change, appsChanged: appsChanged, notify: notify);
    _pendingChanges.add(pending);
    if (!_applyingChanges) {
      _applyPendingChanges();
    }
    return pending.done;
  }

  Future<void> _applyPendingChanges() async {
    _applyingChanges = true;
    try {
      while (_pendingChanges.isNotEmpty) {
        final batch = <_PendingChange>[];
        while (_pendingChanges.isNotEmpty) {
          final pending = _pendingChanges.removeFirst();
          batch.add(pending);
          try {
            await pending.change();
          } catch (error, stackTrace) {
            pending.fail(error, stackTrace);
          }
        }
        try {
          _categories = await _database.listCategoriesWithVisibleApps();
          if (batch.any((pending) => pending.appsChanged)) {
            _applications = await _database.listApplications();
          }
        } catch (error, stackTrace) {
          debugPrint('AppsService: reload failed - $error');
          for (final pending in batch) {
            pending.fail(error, stackTrace);
          }
        }
        if (!_disposed && batch.any((pending) => pending.notify)) {
          notifyListeners();
        }
        for (final pending in batch) {
          pending.complete();
        }
      }
    } finally {
      _applyingChanges = false;
    }
  }

  Future<void> _onAppsChanged(PackageEvent event) async {
    _announceAddedPackage(event);
    try {
      await _apply(() => _applyPackageEvent(event), appsChanged: true);
    } catch (e) {
      debugPrint('AppsService: package event failed - $e');
    }
  }

  void _announceAddedPackage(PackageEvent event) {
    if (event.kind != PackageEventKind.added && event.kind != PackageEventKind.changed) {
      return;
    }
    if (!_packageAddedController.isClosed) {
      _packageAddedController.add(event.apps.single.packageName);
    }
  }

  Future<void> _applyPackageEvent(PackageEvent event) async {
    try {
      switch (event.kind) {
        case PackageEventKind.added:
        case PackageEventKind.changed:
        case PackageEventKind.available:
          await _persistReportedApps(event.apps);
          break;
        case PackageEventKind.removed:
          await _database.deleteApps([event.removedPackageName!]);
          break;
      }
    } finally {
      await _defaultCategories.pinTvApplicationsFirst();
    }
  }

  /// Saves apps the system reported as added, changed or available, without
  /// undoing the user's choice to hide or show them, and files new ones into
  /// their default category.
  Future<void> _persistReportedApps(List<InstalledApp> reportedApps) async {
    final companions = <AppsCompanion>[];
    final candidates = <DefaultCategoryCandidate>[];
    for (final app in reportedApps) {
      final existing = await _database.getApp(app.packageName);
      companions.add(_reportedApp(app, hiddenToKeep: RestoredApps.hiddenToKeep(existing)));
      candidates.add(DefaultCategoryCandidate.fromInstalledApp(app));
    }
    await _database.persistApps(companions);
    await _defaultCategories.fileUncategorised(candidates);
  }

  AppsCompanion _reportedApp(InstalledApp app, {required bool? hiddenToKeep}) => AppsCompanion(
        packageName: Value(app.packageName),
        name: Value(app.name),
        version: Value(app.version ?? "(unknown)"),
        banner: Value(app.banner),
        icon: Value(app.icon),
        hidden: Value(hiddenToKeep ?? (app.isSystemApp || app.packageName == DefaultCategories.launcherPackageName)),
        sideloaded: Value(app.sideloaded),
        isSystemApp: Value(app.isSystemApp),
      );

  /// Saves the apps the system lists and drops the ones it no longer has.
  Future<void> _syncWithSystem() => _database.transaction(() async {
        final existingApps = await _database.listApplications();
        final existingAppsByPackageName = <String, App>{
          for (final app in existingApps) app.packageName: app,
        };

        final appsFromSystem = (await _fLauncherChannel.getInstalledApps())
            .map((app) => _reportedApp(
                  app,
                  hiddenToKeep: RestoredApps.hiddenToKeep(existingAppsByPackageName[app.packageName]),
                ))
            .toList();

        final packageNamesFromSystem = appsFromSystem.map((app) => app.packageName.value).toSet();
        final uninstalledApplications = <String>[];
        for (final existing in existingApps) {
          if (packageNamesFromSystem.contains(existing.packageName) || RestoredApps.isAwaitingInstall(existing)) {
            continue;
          }
          if (!(await _fLauncherChannel.applicationExists(existing.packageName))) {
            uninstalledApplications.add(existing.packageName);
          }
        }

        await _database.persistApps(appsFromSystem);
        await _database.deleteApps(uninstalledApplications);
      });

  Future<void> launchApp(App app) => _fLauncherChannel.launchApp(app.packageName);

  /// Shows what a backup restore wrote to the database.
  Future<void> reloadAfterRestore() => _apply(() async {}, appsChanged: true);

  Future<void> openAppInfo(App app) => _fLauncherChannel.openAppInfo(app.packageName);

  Future<void> uninstallApp(App app) => _fLauncherChannel.uninstallApp(app.packageName);

  Future<void> openSettings() => _fLauncherChannel.openSettings();

  Future<void> openWifiSettings() => _fLauncherChannel.openWifiSettings();

  Future<bool> isDefaultLauncher() => _fLauncherChannel.isDefaultLauncher();

  Future<void> startAmbientMode() => _fLauncherChannel.startAmbientMode();

  Future<void> addToCategory(App app, Category category, {bool shouldNotifyListeners = true}) => _apply(
        () => _defaultCategories.appendToCategory(category.id, [app.packageName]),
        notify: shouldNotifyListeners,
      );

  Future<void> removeFromCategory(App app, Category category) =>
      _apply(() => _database.deleteAppCategory(category.id, app.packageName));

  /// Saves the order [reorderApplication] left in memory for [category].
  Future<void> saveOrderInCategory(Category category) async {
    final applications = _categoriesWithApps.firstWhere((element) => element.category.id == category.id).applications;
    final orderedAppCategories = <AppsCategoriesCompanion>[
      for (int i = 0; i < applications.length; ++i)
        AppsCategoriesCompanion(
          categoryId: Value(category.id),
          appPackageName: Value(applications[i].packageName),
          order: Value(i),
        )
    ];
    await _apply(() => _database.replaceAppsCategories(orderedAppCategories));
  }

  void reorderApplication(Category category, int oldIndex, int newIndex) {
    final applications = _categoriesWithApps.firstWhere((element) => element.category.id == category.id).applications;
    final application = applications.removeAt(oldIndex);
    applications.insert(newIndex, application);
    notifyListeners();
  }

  Future<void> addCategory(String categoryName, {bool shouldNotifyListeners = true}) => _apply(
        () => _defaultCategories.addCategoryOnTop(categoryName),
        notify: shouldNotifyListeners,
      );

  Future<void> renameCategory(Category category, String categoryName) =>
      _apply(() => _database.updateCategory(category.id, CategoriesCompanion(name: Value(categoryName))));

  Future<void> deleteCategory(Category category) => _apply(() => _database.deleteCategory(category.id));

  /// Moves the category in memory at once, then saves the new order.
  Future<void> moveCategory(int oldIndex, int newIndex) async {
    final categoryWithApps = _categoriesWithApps.removeAt(oldIndex);
    _categoriesWithApps.insert(newIndex, categoryWithApps);
    _categoriesWithAppsView = null;
    final orderedCategories = <CategoriesCompanion>[
      for (int i = 0; i < _categoriesWithApps.length; ++i)
        CategoriesCompanion(id: Value(_categoriesWithApps[i].category.id), order: Value(i))
    ];
    await _apply(() => _database.updateCategories(orderedCategories));
  }

  Future<void> hideApplication(App application) => _apply(
        () => _database.updateApp(application.packageName, AppsCompanion(hidden: Value(true))),
        appsChanged: true,
      );

  Future<void> unHideApplication(App application) => _apply(
        () => _database.updateApp(application.packageName, AppsCompanion(hidden: Value(false))),
        appsChanged: true,
      );

  Future<void> setCategoryType(Category category, CategoryType type, {bool shouldNotifyListeners = true}) => _apply(
        () => _database.updateCategory(category.id, CategoriesCompanion(type: Value(type))),
        notify: shouldNotifyListeners,
      );

  Future<void> setCategorySort(Category category, CategorySort sort) =>
      _apply(() => _database.updateCategory(category.id, CategoriesCompanion(sort: Value(sort))));

  Future<void> setCategoryColumnsCount(Category category, int columnsCount) =>
      _apply(() => _database.updateCategory(category.id, CategoriesCompanion(columnsCount: Value(columnsCount))));

  Future<void> setCategoryRowHeight(Category category, int rowHeight) =>
      _apply(() => _database.updateCategory(category.id, CategoriesCompanion(rowHeight: Value(rowHeight))));
}

/// One queued change and the Future its caller waits on.
class _PendingChange {
  final Future<void> Function() change;
  final bool appsChanged;
  final bool notify;
  final Completer<void> _completer = Completer<void>();
  Object? _error;
  StackTrace? _stackTrace;

  _PendingChange(this.change, {required this.appsChanged, required this.notify});

  Future<void> get done => _completer.future;

  /// Keeps the first error: the change's own, else the reload's.
  void fail(Object error, StackTrace stackTrace) {
    if (_error != null) {
      return;
    }
    _error = error;
    _stackTrace = stackTrace;
  }

  void complete() {
    final error = _error;
    if (error != null) {
      _completer.completeError(error, _stackTrace);
    } else {
      _completer.complete();
    }
  }
}
