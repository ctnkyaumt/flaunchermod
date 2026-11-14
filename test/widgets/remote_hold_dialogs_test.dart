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

// Everything a test awaits (the database, the apps service, the fake
// channel's pending launch) is created inside the test body. testWidgets runs
// the body in a fake-async zone that only runs its own microtasks; a future
// created in setUp completes in the real zone, which the body never yields
// to, so awaiting it would stall the test.

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = const Size(1280, 720);
    binding.window.devicePixelRatioTestValue = 1;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.clearPhysicalSizeTestValue();
    binding.window.clearDevicePixelRatioTestValue();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('Holding OK on a category adds the app once and closes only the dialog', (tester) async {
    final launcher = await _start(tester);
    try {
      final app = _app(launcher.apps);
      await _pumpHome(
          tester, launcher.apps, (context) => showDialog<void>(context: context, builder: (_) => AddToCategoryDialog(app)));
      await _openFromHome(tester);
      Focus.of(tester.element(find.text('Games'))).requestFocus();
      await tester.pump();

      // OK goes down and Android repeats it. The messages are dispatched back
      // to back, so the add (database work) is still in flight for every repeat.
      await Future.wait([
        _sendAndroidKey(tester, 'keydown', 23),
        for (var repeat = 1; repeat <= 3; repeat++) _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat),
      ]);
      await _pumpUntil(tester, () => _appsIn(launcher.apps, 'Games').isNotEmpty);
      // Still held after the add finished.
      for (var repeat = 4; repeat <= 6; repeat++) {
        await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
        await tester.pump();
      }
      await _sendAndroidKey(tester, 'keyup', 23);
      await _pumpRouteTransition(tester);

      expect(_appsIn(launcher.apps, 'Games'), ['a.app']);
      expect(find.byType(AddToCategoryDialog), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _stop(tester, launcher);
    }
  });

  testWidgets('Holding OK on Open launches the app once and closes only the panel', (tester) async {
    final launcher = await _start(tester);
    try {
      final app = _app(launcher.apps);
      await _pumpHome(
        tester,
        launcher.apps,
        (context) => showDialog<ApplicationInfoPanelResult>(
          context: context,
          builder: (_) => ApplicationInfoPanel(category: null, application: app),
        ),
      );
      await _openFromHome(tester);
      Focus.of(tester.element(find.text('Open'))).requestFocus();
      await tester.pump();

      // The launch stays pending until the test completes it.
      await _sendAndroidKey(tester, 'keydown', 23);
      await tester.pump();
      for (var repeat = 1; repeat <= 3; repeat++) {
        await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
        await tester.pump();
      }
      expect(launcher.system.launches, ['a.app']);
      launcher.system.launch.complete();
      await tester.pump();
      for (var repeat = 4; repeat <= 6; repeat++) {
        await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
        await tester.pump();
      }
      await _sendAndroidKey(tester, 'keyup', 23);
      await _pumpRouteTransition(tester);

      expect(launcher.system.launches, ['a.app']);
      expect(find.byType(ApplicationInfoPanel), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _stop(tester, launcher);
    }
  });

  testWidgets('Holding OK on Hide hides the app and closes only the panel', (tester) async {
    final launcher = await _start(tester);
    try {
      final app = _app(launcher.apps);
      await _pumpHome(
        tester,
        launcher.apps,
        (context) => showDialog<ApplicationInfoPanelResult>(
          context: context,
          builder: (_) => ApplicationInfoPanel(category: null, application: app),
        ),
      );
      await _openFromHome(tester);
      Focus.of(tester.element(find.text('Hide'))).requestFocus();
      await tester.pump();

      // Dispatched back to back: the hide is still being written for every repeat.
      await Future.wait([
        _sendAndroidKey(tester, 'keydown', 23),
        for (var repeat = 1; repeat <= 3; repeat++) _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat),
      ]);
      await _pumpUntil(tester, () => _app(launcher.apps).hidden);
      for (var repeat = 4; repeat <= 6; repeat++) {
        await _sendAndroidKey(tester, 'keydown', 23, repeatCount: repeat);
        await tester.pump();
      }
      await _sendAndroidKey(tester, 'keyup', 23);
      await _pumpRouteTransition(tester);

      expect(_app(launcher.apps).hidden, isTrue);
      expect(find.byType(ApplicationInfoPanel), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _stop(tester, launcher);
    }
  });
}

class _Launcher {
  _Launcher(this.database, this.system, this.apps);

  final FLauncherDatabase database;
  final _SystemApps system;
  final AppsService apps;
}

/// Starts the launcher's app list on an empty in-memory database that also
/// has a "Games" category, with the system reporting one installed app.
Future<_Launcher> _start(WidgetTester tester) async {
  // Remote keys only arrive while the launcher is in the foreground.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final database = FLauncherDatabase.inMemory();
  await database.insertCategory(CategoriesCompanion.insert(name: 'Games', order: 5));
  final system = _SystemApps();
  final apps = AppsService(system, database);
  await _pumpUntil(tester, () => apps.initialized);
  return _Launcher(database, system, apps);
}

Future<void> _stop(WidgetTester tester, _Launcher launcher) async {
  await tester.pumpWidget(const SizedBox());
  launcher.apps.dispose();
  await launcher.database.close();
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
  await tester.pump();
}

Future<void> _openFromHome(WidgetTester tester) async {
  await tester.tap(find.text('Details'));
  await _pumpRouteTransition(tester);
}

/// Runs a dialog's open or close transition (150 ms) to its end.
Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

/// Sends an Android remote key message. The key is handled before this
/// returns; only the reply to the platform completes later.
Future<void> _sendAndroidKey(WidgetTester tester, String type, int keyCode, {int repeatCount = 0}) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.keyEvent.name,
      SystemChannels.keyEvent.codec.encodeMessage({
        'type': type, 'keymap': 'android', 'keyCode': keyCode, 'scanCode': keyCode == 23 ? 353 : 0,
        'metaState': 0, 'flags': 0, 'source': 257, 'repeatCount': repeatCount,
        'deviceId': -1, 'plainCodePoint': 0, 'codePoint': 0,
      }),
      (_) {},
    );

/// Pumps a bounded number of frames until [ready] holds. The database and
/// the fake channel complete through microtasks, which each pump runs.
Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 20 && !ready(); frame++) {
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'The work did not finish');
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
