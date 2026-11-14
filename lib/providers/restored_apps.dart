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

import 'package:drift/drift.dart' show Value;
import 'package:flauncher/database.dart';

/// The rule for apps a backup restore wrote before this TV reported them.
///
/// A restore keeps every app the backup lists. An app this database does not
/// know yet gets a placeholder row: version "" (only the system reports a
/// version), hidden while it is not installed here, and its category
/// positions from the backup. Such a placeholder:
/// - is never deleted as "uninstalled" at startup while it waits for the app;
/// - is shown automatically once the system reports the app (its hidden flag
///   is then the default for a new app, not the placeholder's).
class RestoredApps {
  RestoredApps._();

  static const placeholderVersion = "";

  static bool isPlaceholderVersion(String version) => version == placeholderVersion;

  static bool isPlaceholder(App app) => isPlaceholderVersion(app.version);

  /// A restored app that is not installed yet: kept with its category
  /// positions although the system does not list it.
  static bool isAwaitingInstall(App app) => isPlaceholder(app) && app.hidden;

  /// The hidden flag to keep when the system reports [existing] as added,
  /// changed or available. Null means "use the default for a new app".
  static bool? hiddenToKeep(App? existing) =>
      existing == null || isPlaceholder(existing) ? null : existing.hidden;

  /// Hidden flag a restore gives an app: hidden until it is installed here.
  static bool hiddenOnRestore({required bool hiddenInBackup, required bool installed}) =>
      hiddenInBackup || !installed;

  /// Row for an app the backup lists but this database does not know.
  static AppsCompanion placeholder({
    required String packageName,
    required String name,
    required bool hidden,
    required bool sideloaded,
    required bool isSystemApp,
  }) =>
      AppsCompanion.insert(
        packageName: packageName,
        name: name,
        version: placeholderVersion,
        hidden: Value(hidden),
        sideloaded: Value(sideloaded),
        isSystemApp: Value(isSystemApp),
      );
}
