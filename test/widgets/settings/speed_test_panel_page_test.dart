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

import 'package:flauncher/providers/speed_test_service.dart';
import 'package:flauncher/widgets/settings/speed_test_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Remote OK starts and cancels once while keeping the button focused', (tester) async {
    final service = _FakeSpeedTestService();
    await _open(tester, service);
    await _remote(tester, 23);
    expect(service.starts, 1);
    expect(find.text('Cancel test'), findsOneWidget);
    expect(Focus.of(tester.element(find.text('Cancel test'))).hasFocus, isTrue);
    await _remote(tester, 23);
    expect(service.cancels, 1);
    expect(find.text('Test cancelled'), findsOneWidget);
    expect(Focus.of(tester.element(find.text('Start test'))).hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('Android Back leaves the page and cancels active traffic', (tester) async {
    final service = _FakeSpeedTestService();
    await _open(tester, service);
    await _remote(tester, 23);
    await _remote(tester, 4);
    await tester.pumpAndSettle();
    expect(find.byType(SpeedTestPanelPage), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(service.cancels, 1);
    service.dispose();
  });

  testWidgets('Backgrounding stops the active test', (tester) async {
    final service = _FakeSpeedTestService();
    await _open(tester, service);
    await _remote(tester, 23);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(service.cancels, 1);
    expect(find.text('Test cancelled'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('Shows numeric results, traffic disclosure, and failure retry', (tester) async {
    final service = _FakeSpeedTestService();
    await _open(tester, service);
    service.finish();
    await tester.pumpAndSettle();
    expect(find.text('92.4'), findsOneWidget);
    expect(find.text('18.2'), findsOneWidget);
    expect(find.text('HTTPS latency  24 ms'), findsOneWidget);
    expect(find.textContaining('192 MiB'), findsOneWidget);
    expect(find.text('Test complete'), findsOneWidget);
    service.fail();
    await tester.pumpAndSettle();
    expect(find.text('Offline. Please retry.'), findsOneWidget);
    await _remote(tester, 23);
    expect(service.starts, 1);
    await tester.pumpWidget(const SizedBox());
    expect(service.cancels, 1);
    service.dispose();
  });
}

Future<void> _open(WidgetTester tester, SpeedTestService service) async {
  await tester.pumpWidget(MaterialApp(
    shortcuts: {...WidgetsApp.defaultShortcuts, SingleActivator(LogicalKeyboardKey.select): ActivateIntent()},
    home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        autofocus: true,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(body: Center(child: SizedBox(width: 318, child: SpeedTestPanelPage(service: service)))),
        )),
        child: const Text('Settings'),
      ),
    )),
  ));
  await tester.pumpAndSettle();
  await _remote(tester, 23);
  await tester.pumpAndSettle();
}

Future<void> _remote(WidgetTester tester, int code) async {
  for (final type in ['keydown', 'keyup']) {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/keyevent',
      const JSONMessageCodec().encodeMessage({
        'type': type, 'keymap': 'android', 'flags': 0, 'plainCodePoint': 0,
        'codePoint': 0, 'keyCode': code, 'scanCode': 0, 'metaState': 0,
        'source': 257, 'deviceId': 1, 'repeatCount': 0,
      }),
      (_) {},
    );
    await tester.pump();
  }
}

class _FakeSpeedTestService extends SpeedTestService {
  bool running = false;
  int starts = 0;
  int cancels = 0;
  @override
  bool get isRunning => running;
  @override
  Future<void> start() async {
    if (running) return;
    starts++;
    running = true;
    phase = SpeedTestPhase.download;
    notifyListeners();
  }
  @override
  void cancel() {
    if (!running) return;
    cancels++;
    running = false;
    phase = SpeedTestPhase.cancelled;
    notifyListeners();
  }
  void finish() {
    running = false;
    latencyMs = 24;
    downloadMbps = 92.4;
    uploadMbps = 18.2;
    phase = SpeedTestPhase.complete;
    notifyListeners();
  }
  void fail() {
    running = false;
    phase = SpeedTestPhase.failed;
    error = 'Offline. Please retry.';
    notifyListeners();
  }
}
