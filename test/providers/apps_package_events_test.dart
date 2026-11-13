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

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FLauncherDatabase database;
  late _SystemApps system;
  AppsService? service;

  setUp(() {
    database = FLauncherDatabase.inMemory();
    system = _SystemApps();
  });
  tearDown(() async {
    service?.dispose();
    service = null;
    await database.close();
  });

  Future<AppsService> launch() async {
    final launched = AppsService(system, database);
    service = launched;
    await _nextChange(launched, until: () => launched.initialized);
    return launched;
  }

  App app(AppsService apps, String packageName) =>
      apps.applications.firstWhere((candidate) => candidate.packageName == packageName);

  test("an app the user hid stays hidden when it is updated", () async {
    await database.persistApps([
      AppsCompanion.insert(packageName: "user.app", name: "User app", version: "1", hidden: Value(true)),
    ]);
    system.installed = [_appInfo("user.app", version: "1")];
    final apps = await launch();

    await system.report({"action": "PACKAGE_CHANGED", "activitiyInfo": _appInfo("user.app", version: "2")});

    expect(app(apps, "user.app").version, "2");
    expect(app(apps, "user.app").hidden, isTrue);
  });

  test("a system app the user chose to show stays shown when it changes", () async {
    await database.persistApps([
      AppsCompanion.insert(packageName: "system.app", name: "System app", version: "1", hidden: Value(false)),
    ]);
    system.installed = [_appInfo("system.app", version: "1", isSystemApp: true)];
    final apps = await launch();

    await system.report({
      "action": "PACKAGE_CHANGED",
      "activitiyInfo": _appInfo("system.app", version: "2", isSystemApp: true),
    });

    expect(app(apps, "system.app").hidden, isFalse);
  });

  test("a restored app installed while the launcher was closed is shown at the next start", () async {
    await database.persistApps([
      AppsCompanion.insert(packageName: "restored.app", name: "Restored", version: "", hidden: Value(true)),
    ]);
    system.installed = [_appInfo("restored.app", version: "3")];

    final apps = await launch();

    expect(app(apps, "restored.app").version, "3");
    expect(app(apps, "restored.app").hidden, isFalse);
  });

  test("a restored app is shown when it is installed while the launcher runs", () async {
    await database.persistApps([
      AppsCompanion.insert(packageName: "restored.app", name: "Restored", version: "", hidden: Value(true)),
    ]);
    final apps = await launch();

    await system.report({"action": "PACKAGE_ADDED", "activitiyInfo": _appInfo("restored.app", version: "3")});

    expect(app(apps, "restored.app").hidden, isFalse);
  });

  test("a batch with a package that has nothing to launch still adds the others", () async {
    final apps = await launch();

    await system.report({
      "action": "PACKAGES_AVAILABLE",
      "activitiesInfo": [null, _appInfo("sdcard.app", version: "1")],
    });

    expect(apps.applications.map((app) => app.packageName), contains("sdcard.app"));
  });

  test("the saved apps are shown when the system cannot list installed apps", () async {
    await database.persistApps([
      AppsCompanion.insert(packageName: "saved.app", name: "Saved", version: "1"),
    ]);
    system.listingFails = true;

    final apps = await launch();

    expect(apps.initialized, isTrue);
    expect(apps.applications.map((app) => app.packageName), contains("saved.app"));
  });
}

Map<String, dynamic> _appInfo(String packageName, {required String version, bool isSystemApp = false}) => {
      "packageName": packageName,
      "name": packageName,
      "version": version,
      "banner": null,
      "icon": null,
      "sideloaded": false,
      "isSystemApp": isSystemApp,
    };

/// Completes at the service's first notification for which [until] holds.
Future<void> _nextChange(AppsService service, {required bool Function() until}) {
  final changed = Completer<void>();
  late void Function() listener;
  listener = () {
    if (!until()) return;
    service.removeListener(listener);
    changed.complete();
  };
  service.addListener(listener);
  return changed.future.timeout(const Duration(seconds: 5));
}

/// Stands in for Android's package manager on the other side of the channel.
class _SystemApps extends FLauncherChannel {
  List<Map<String, dynamic>> installed = [];
  bool listingFails = false;
  void Function(Map<dynamic, dynamic>)? _listener;

  @override
  Future<List<dynamic>> getApplications() async {
    if (listingFails) throw PlatformException(code: "native_error");
    return installed;
  }

  @override
  Future<bool> applicationExists(String packageName) async =>
      installed.any((app) => app["packageName"] == packageName);

  @override
  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) => _listener = listener;

  /// Delivers a package event and waits until the service has taken it in.
  Future<void> report(Map<dynamic, dynamic> event) async {
    final handled = (_listener! as dynamic Function(Map<dynamic, dynamic>))(event);
    if (handled is Future) await handled;
  }
}
