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

import 'package:flauncher/widgets/settings/engineering_menu_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methodChannel = MethodChannel('me.efesser.flauncher/method');

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());
  tearDown(() => _methodChannel.setMockMethodCallHandler(null));

  testWidgets('Lists Design Menu and Factory Menu with Design Menu focused first', (tester) async {
    await _pump(tester, (call) async => true);

    expect(find.text('Engineering Menu'), findsOneWidget);
    expect(find.text('Design Menu'), findsOneWidget);
    expect(find.text('Factory Menu'), findsOneWidget);
    expect(Focus.of(tester.element(find.text('Design Menu'))).hasPrimaryFocus, isTrue);
  });

  testWidgets('Design Menu and Factory Menu ask the device for the matching menu', (tester) async {
    final calls = <MethodCall>[];
    await _pump(tester, (call) async {
      calls.add(call);
      return true;
    });

    await tester.tap(find.text('Design Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factory Menu'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), ['openEngineeringMenu', 'openEngineeringMenu']);
    expect(calls.map((call) => call.arguments), [
      {'menu': 'design'},
      {'menu': 'factory'},
    ]);
    expect(find.textContaining('Could not open'), findsNothing);
  });

  testWidgets('A menu the device lacks shows a failure message', (tester) async {
    await _pump(tester, (call) async => false);

    await tester.tap(find.text('Design Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open Design Menu'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.text('Factory Menu'))).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factory Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open Factory Menu'), findsOneWidget);
  });

  testWidgets('A native error shows the same failure message', (tester) async {
    await _pump(tester, (call) async => throw PlatformException(code: 'native_error', message: 'boom'));

    await tester.tap(find.text('Factory Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open Factory Menu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Taps while a request is pending are ignored, then work again', (tester) async {
    final pending = Completer<bool>();
    final calls = <MethodCall>[];
    await _pump(tester, (call) {
      calls.add(call);
      return pending.future;
    });

    await tester.tap(find.text('Design Menu'));
    await tester.pump();
    await tester.tap(find.text('Design Menu'));
    await tester.pump();
    await tester.tap(find.text('Factory Menu'));
    await tester.pump();
    expect(calls.length, 1);

    pending.complete(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factory Menu'));
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    expect(calls.last.arguments, {'menu': 'factory'});
  });
}

Future<void> _pump(WidgetTester tester, Future<dynamic> Function(MethodCall call) handler) async {
  _methodChannel.setMockMethodCallHandler(handler);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: EngineeringMenuPanelPage())));
  await tester.pumpAndSettle();
}
