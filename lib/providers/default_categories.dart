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

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel_contract.dart';

/// An app that may need a place on the home screen.
class DefaultCategoryCandidate {
  final String packageName;
  final bool sideloaded;
  final bool isSystemApp;

  const DefaultCategoryCandidate({required this.packageName, required this.sideloaded, required this.isSystemApp});

  /// An app the system reported as installed.
  DefaultCategoryCandidate.fromInstalledApp(InstalledApp app)
      : packageName = app.packageName,
        sideloaded = app.sideloaded,
        isSystemApp = app.isSystemApp;
}

/// Where apps go when the user has not placed them: "TV Applications", or
/// "Non-TV Applications" for sideloaded apps.
///
/// Writes to the database only; it never reads apps with their icons or
/// banners. Callers refresh what they show afterwards.
class DefaultCategories {
  static const launcherPackageName = "me.efesser.flauncher";
  static const tvCategoryName = "TV Applications";
  static const nonTvCategoryName = "Non-TV Applications";

  final FLauncherDatabase _database;

  DefaultCategories(this._database);

  static String categoryNameFor({required bool sideloaded}) => sideloaded ? nonTvCategoryName : tvCategoryName;

  /// Files user-visible apps that are in no category into their default
  /// category, creating that category (on top) if it does not exist.
  /// System apps and the launcher itself are left out.
  Future<void> fileUncategorised(Iterable<DefaultCategoryCandidate> apps) async {
    final packageNamesByCategory = <String, List<String>>{};
    for (final app in apps) {
      if (app.isSystemApp || app.packageName == launcherPackageName) {
        continue;
      }
      if (await _database.isAppInAnyCategory(app.packageName)) {
        continue;
      }
      packageNamesByCategory.putIfAbsent(categoryNameFor(sideloaded: app.sideloaded), () => []).add(app.packageName);
    }
    for (final entry in packageNamesByCategory.entries) {
      final existing = (await _database.listCategories()).firstWhereOrNull((c) => c.name == entry.key);
      final categoryId = existing?.id ?? await addCategoryOnTop(entry.key);
      await appendToCategory(categoryId, entry.value);
    }
  }

  /// First start: every known app goes to its default category, with
  /// "TV Applications" on top as a row.
  Future<void> createInitialCategories(List<App> apps) => _database.transaction(() async {
        final nonTvApps = apps.where((app) => app.sideloaded).map((app) => app.packageName).toList();
        final tvApps = apps.where((app) => !app.sideloaded).map((app) => app.packageName).toList();
        if (nonTvApps.isNotEmpty) {
          await appendToCategory(await addCategoryOnTop(nonTvCategoryName), nonTvApps);
        }
        if (tvApps.isNotEmpty) {
          final tvCategoryId = await addCategoryOnTop(tvCategoryName);
          await _database.updateCategory(tvCategoryId, CategoriesCompanion(type: Value(CategoryType.row)));
          await appendToCategory(tvCategoryId, tvApps);
        }
      });

  /// Keeps "TV Applications" first and shown as a row; writes only when needed.
  Future<void> pinTvApplicationsFirst() => _database.transaction(() async {
        final categories = (await _database.listCategories()).toList();
        final tvIndex = categories.indexWhere((c) => c.name == tvCategoryName);
        if (tvIndex == -1) {
          return;
        }
        final tvCategory = categories.removeAt(tvIndex);
        categories.insert(0, tvCategory);
        if (tvCategory.type != CategoryType.row) {
          await _database.updateCategory(tvCategory.id, CategoriesCompanion(type: Value(CategoryType.row)));
        }
        if (tvIndex != 0) {
          await _database.updateCategories([
            for (int i = 0; i < categories.length; i++)
              CategoriesCompanion(id: Value(categories[i].id), order: Value(i))
          ]);
        }
      });

  /// Adds a category above all others and returns its id.
  Future<int> addCategoryOnTop(String name) async {
    final existing = await _database.listCategories();
    final id = await _database.into(_database.categories).insert(CategoriesCompanion.insert(name: name, order: 0));
    await _database.updateCategories([
      for (int i = 0; i < existing.length; i++) CategoriesCompanion(id: Value(existing[i].id), order: Value(i + 1))
    ]);
    return id;
  }

  /// Appends [packageNames] to the end of a category in one batch.
  Future<void> appendToCategory(int categoryId, List<String> packageNames) async {
    if (packageNames.isEmpty) {
      return;
    }
    var order = await _database.nextAppCategoryOrder(categoryId) ?? 0;
    await _database.insertAppsCategories([
      for (final packageName in packageNames)
        AppsCategoriesCompanion.insert(categoryId: categoryId, appPackageName: packageName, order: order++)
    ]);
  }
}
