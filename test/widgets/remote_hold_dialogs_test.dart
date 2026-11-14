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

import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/add_to_category_dialog.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late FLauncherDatabase database;
  late _SystemApps system;
  late AppsService apps;

  setUp(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = const Size(1280, 720);
    binding.window.devicePixelRatioTestValue = 1;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
    database = FLauncherDatabase.inMemory();
    await database.insertCategory(CategoriesCompanion.insert(name: 'Games', order: 5));
    system = _SystemApps();
    apps = AppsService(system, database);
    await _initialized(apps);
  });

  tearDown(() async {
    apps.dispose();
    await database.close();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.clearPhysicalSizeTestValue();
    binding.window.clearDevicePixelRatioTestValue();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('Holding OK on a category adds the app once and closes only the dialog', (tester) async {
    final app = _app(apps);
    await _pumpHome(tester, apps, (context) => showDialog<void>(context: context, builder: (_) => AddToCategoryDialog(app)));
    await _openFromHome(tester);
    Focus.of(tester.element(find.text('Games'))).requestFocus();
    await tester.pump();

    // Android sends repeated key-downs while OK is held.
    await _sendAndroidKey(tester, 'keydown', 23);
    for (var repeat = 1; repeat <= 3; repeat++) {
      await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
    }
    await _pumpUntil(tester, () => _appsIn(apps, 'Games').isNotEmpty);
    for (var repeat = 4; repeat <= 6; repeat++) {
      await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
      await tester.pump();
    }
    await _sendAndroidKey(tester, 'keyup', 23);
    await tester.pumpAndSettle();

    expect(_appsIn(apps, 'Games'), ['a.app']);
    expect(find.byType(AddToCategoryDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Holding OK on Open launches the app once and closes only the panel', (tester) async {
    final app = _app(apps);
    await _pumpHome(
      tester,
      apps,
      (context) => showDialog<ApplicationInfoPanelResult>(
        context: context,
        builder: (_) => ApplicationInfoPanel(category: null, application: app),
      ),
    );
    await _openFromHome(tester);
    Focus.of(tester.element(find.text('Open'))).requestFocus();
    await tester.pump();

    await _sendAndroidKey(tester, 'keydown', 23);
    await tester.pump();
    for (var repeat = 1; repeat <= 3; repeat++) {
      await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
      await tester.pump();
    }
    expect(system.launches, ['a.app']);
    system.launch.complete();
    await tester.pump();
    for (var repeat = 4; repeat <= 6; repeat++) {
      await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
      await tester.pump();
    }
    await _sendAndroidKey(tester, 'keyup', 23);
    await tester.pumpAndSettle();

    expect(system.launches, ['a.app']);
    expect(find.byType(ApplicationInfoPanel), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('Holding OK on Hide hides the app and closes only the panel', (tester) async {
    final app = _app(apps);
    await _pumpHome(
      tester,
      apps,
      (context) => showDialog<ApplicationInfoPanelResult>(
        context: context,
        builder: (_) => ApplicationInfoPanel(category: null, application: app),
      ),
    );
    await _openFromHome(tester);
    Focus.of(tester.element(find.text('Hide'))).requestFocus();
    await tester.pump();

    await _sendAndroidKey(tester, 'keydown', 23);
    for (var repeat = 1; repeat <= 3; repeat++) {
      await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
    }
    await _pumpUntil(tester, () => _app(apps).hidden);
    for (var repeat = 4; repeat <= 6; repeat++) {
      await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
      await tester.pump();
    }
    await _sendAndroidKey(tester, 'keyup', 23);
    await tester.pumpAndSettle();

    expect(_app(apps).hidden, isTrue);
    expect(find.byType(ApplicationInfoPanel), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

App _app(AppsService apps) => apps.applications.firstWhere((app) => app.packageName == 'a.app');

List<String> _appsIn(AppsService apps, String categoryName) => apps.categoriesWithApps
    .firstWhere((item) => item.category.name == categoryName)
    .applications
    .map((app) => app.packageName)
    .toList();

Future<void> _pumpHome(WidgetTester tester, AppsService apps, void Function(BuildContext) open) async {
  await tester.pumpWidget(ChangeNotifierProvider<AppsService>.value(
    value: apps,
    child: MaterialApp(
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const Text('Home'),
            TextButton(autofocus: true, onPressed: () => open(context), child: const Text('Details')),
          ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openFromHome(WidgetTester tester) async {
  await tester.tap(find.text('Details'));
  await tester.pumpAndSettle();
}

Future<void> _sendAndroidKey(WidgetTester tester, String type, int keyCode, {int repeatCount = 0}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.keyEvent.name,
    SystemChannels.keyEvent.codec.encodeMessage({
      'type': type, 'keymap': 'android', 'keyCode': keyCode, 'scanCode': keyCode == 23 ? 353 : 0,
      'metaState': 0, 'flags': 0, 'source': 257, 'repeatCount': repeatCount,
      'deviceId': -1, 'plainCodePoint': 0, 'codePoint': 0,
    }),
    (_) {},
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'The action did not finish');
}

Future<void> _initialized(AppsService apps) {
  if (apps.initialized) return Future.value();
  final done = Completer<void>();
  void listener() {
    if (apps.initialized && !done.isCompleted) done.complete();
  }

  apps.addListener(listener);
  return done.future.timeout(const Duration(seconds: 5)).whenComplete(() => apps.removeListener(listener));
}

/// Stands in for Android's package manager and activity launcher.
class _SystemApps extends FLauncherChannel {
  final launches = <String>[];
  final launch = Completer<void>();

  @override
  Future<List<InstalledApp>> getInstalledApps() async =>
      const [InstalledApp(packageName: 'a.app', name: 'a.app', version: '1')];

  @override
  Future<bool> applicationExists(String packageName) async => packageName == 'a.app';

  @override
  void addPackageEventListener(void Function(PackageEvent) listener) {}

  @override
  Future<void> launchApp(String packageName) {
    launches.add(packageName);
    return launch.future;
  }
}
