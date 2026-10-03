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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/device_power_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methodChannel = MethodChannel('me.efesser.flauncher/method');

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());
  tearDown(() => _methodChannel.setMockMethodCallHandler(null));

  testWidgets('Remote opening release keeps Cancel focused and OK dismisses it', (tester) async {
    var requests = 0;
    _methodChannel.setMockMethodCallHandler((call) async {
      requests++;
      return true;
    });
    await _openDialog(tester, remote: true);
    _expectFocused(tester, 'CANCEL');
    expect(RawKeyboard.instance.keysPressed, isEmpty);
    await _pressRemoteKey(tester, 23);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
    expect(requests, 0);
    _expectFocused(tester, 'Power');
  });

  testWidgets('D-pad reaches every choice in both directions without leaving the dialog', (tester) async {
    await _openDialog(tester, remote: true);
    for (final label in ['STANDBY', 'POWER MENU']) {
      await _pressRemoteKey(tester, 22);
      _expectFocused(tester, label);
    }
    for (final label in ['STANDBY', 'CANCEL']) {
      await _pressRemoteKey(tester, 21);
      _expectFocused(tester, label);
    }
    await _pressRemoteKey(tester, 23);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
  });

  testWidgets('Remote Standby dispatches once and moves focus to Close while pending', (tester) async {
    final request = Completer<bool>();
    final methods = <String>[];
    _methodChannel.setMockMethodCallHandler((call) async {
      methods.add(call.method);
      return request.future;
    });
    await _openDialog(tester, remote: true);
    await _pressRemoteKey(tester, 22);
    await _pressRemoteKey(tester, 23);
    expect(methods, ['standbyDevice']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    _expectFocused(tester, 'CLOSE');
    await _pressRemoteKey(tester, 23);
    await tester.pumpAndSettle();
    request.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
    expect(methods, ['standbyDevice']);
    _expectFocused(tester, 'Power');
  });

  testWidgets('Remote Power menu failure keeps Cancel and retry choices reachable', (tester) async {
    final methods = <String>[];
    _methodChannel.setMockMethodCallHandler((call) async {
      methods.add(call.method);
      return call.method == 'standbyDevice';
    });
    await _openDialog(tester, remote: true);
    await _pressRemoteKey(tester, 22);
    await _pressRemoteKey(tester, 22);
    await _pressRemoteKey(tester, 23);
    await tester.pumpAndSettle();
    expect(methods, ['shutdownDevice']);
    expect(find.text('Power request failed'), findsOneWidget);
    _expectFocused(tester, 'CANCEL');
    await _pressRemoteKey(tester, 22);
    _expectFocused(tester, 'STANDBY');
    await _pressRemoteKey(tester, 23);
    await tester.pumpAndSettle();
    expect(methods, ['shutdownDevice', 'standbyDevice']);
    expect(find.byType(DevicePowerDialog), findsNothing);
  });

  testWidgets('Remote timeout returns focus to Cancel and ignores the late reply', (tester) async {
    final request = Completer<bool>();
    _methodChannel.setMockMethodCallHandler((call) async => request.future);
    await _openDialog(tester, remote: true);
    await _pressRemoteKey(tester, 22);
    await _pressRemoteKey(tester, 22);
    await _pressRemoteKey(tester, 23);
    _expectFocused(tester, 'CLOSE');
    await tester.pump(Duration(seconds: 11));
    await tester.pumpAndSettle();
    _expectFocused(tester, 'CANCEL');
    request.complete(true);
    await tester.pumpAndSettle();
    _expectFocused(tester, 'CANCEL');
    await _pressRemoteKey(tester, 23);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
  });

  testWidgets('Power choices distinguish standby from the system menu', (tester) async {
    await _openDialog(tester);
    expect(find.text('STANDBY'), findsOneWidget);
    expect(find.text('POWER MENU'), findsOneWidget);
    expect(find.textContaining('force', findRichText: true), findsNothing);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });

  testWidgets('Accepted power menu closes progress even when the device stays on', (tester) async {
    final request = Completer<bool>();
    _methodChannel.setMockMethodCallHandler((call) async {
      expect(call.method, 'shutdownDevice');
      return request.future;
    });
    await _openDialog(tester);
    await tester.tap(find.text('POWER MENU'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    request.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Unsupported power menu replaces progress with an actionable error', (tester) async {
    _methodChannel.setMockMethodCallHandler((call) async => false);
    await _openDialog(tester);
    await tester.tap(find.text('POWER MENU'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('The power menu is unavailable. Enable the button mapper or use the remote power button.'), findsOneWidget);
    expect(find.text('STANDBY'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });

  testWidgets('No native reply reaches its deadline and ignores a late result', (tester) async {
    final request = Completer<bool>();
    _methodChannel.setMockMethodCallHandler((call) async => request.future);
    await _openDialog(tester);
    await tester.tap(find.text('POWER MENU'));
    await tester.pump();
    await tester.pump(Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('The device did not respond. Try standby or the remote power button.'), findsOneWidget);
    request.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });

  testWidgets('Close dismisses pending progress without late dialogs or navigation', (tester) async {
    final request = Completer<bool>();
    _methodChannel.setMockMethodCallHandler((call) async => request.future);
    await _openDialog(tester);
    await tester.tap(find.text('POWER MENU'));
    await tester.pump();
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    request.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back escapes pending progress and a late error stays dismissed', (tester) async {
    final request = Completer<bool>();
    _methodChannel.setMockMethodCallHandler((call) async => request.future);
    await _openDialog(tester);
    await tester.tap(find.text('POWER MENU'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    request.completeError(PlatformException(code: 'unavailable', message: 'No permission'));
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Repeated activation dispatches only one pending request', (tester) async {
    final request = Completer<bool>();
    var requests = 0;
    _methodChannel.setMockMethodCallHandler((call) async {
      requests++;
      return request.future;
    });
    await _openDialog(tester);
    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'POWER MENU'));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(requests, 1);
    request.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('Android remote Back escapes pending progress', (tester) async {
    final request = Completer<bool>();
    _methodChannel.setMockMethodCallHandler((call) async => request.future);
    await _openDialog(tester);
    await tester.tap(find.text('POWER MENU'));
    await tester.pump();
    for (final type in ['keydown', 'keyup']) {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.keyEvent.name,
        SystemChannels.keyEvent.codec.encodeMessage({
          'type': type, 'keymap': 'android', 'keyCode': 4, 'scanCode': 158,
          'metaState': 0, 'flags': 0, 'source': 257, 'repeatCount': 0,
          'deviceId': -1, 'plainCodePoint': 0, 'codePoint': 0,
        }),
        (_) {},
      );
    }
    await tester.pumpAndSettle();
    request.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Standby uses its own native method', (tester) async {
    _methodChannel.setMockMethodCallHandler((call) async {
      expect(call.method, 'standbyDevice');
      return true;
    });
    await _openDialog(tester);
    await tester.tap(find.text('STANDBY'));
    await tester.pumpAndSettle();
    expect(find.byType(DevicePowerDialog), findsNothing);
  });

  testWidgets('A hidden power dialog never pops the newer route', (tester) async {
    final request = Completer<bool>();
    _methodChannel.setMockMethodCallHandler((call) async => request.future);
    await _openDialog(tester);
    await tester.tap(find.text('POWER MENU'));
    await tester.pump();
    final context = tester.element(find.byType(DevicePowerDialog));
    unawaited(showDialog<void>(context: context, builder: (_) => AlertDialog(title: Text('Other dialog'))));
    await tester.pump();
    request.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Other dialog'), findsOneWidget);
    expect(find.byType(DevicePowerDialog), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}

Future<void> _openDialog(WidgetTester tester, {bool remote = false}) async {
  await tester.pumpWidget(MaterialApp(
    shortcuts: {
      ...WidgetsApp.defaultShortcuts,
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    },
    home: Builder(
      builder: (context) => Scaffold(
        body: Column(children: [
          Text('Home'),
          TextButton(
            autofocus: true,
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => DevicePowerDialog(channel: FLauncherChannel()),
            ),
            child: Text('Power'),
          ),
        ]),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  if (remote) {
    // Opening OK's release arrives after focus has moved onto the dialog.
    await _sendAndroidKey(tester, 'keydown', 23);
    await tester.pumpAndSettle();
    await _sendAndroidKey(tester, 'keyup', 23);
  } else {
    await tester.tap(find.text('Power'));
  }
  await tester.pumpAndSettle();
}

void _expectFocused(WidgetTester tester, String label) =>
    expect(Focus.of(tester.element(find.text(label))).hasPrimaryFocus, isTrue, reason: '$label must own remote focus');

Future<void> _pressRemoteKey(WidgetTester tester, int keyCode) async {
  await _sendAndroidKey(tester, 'keydown', keyCode);
  await tester.pump();
  await _sendAndroidKey(tester, 'keyup', keyCode);
  await tester.pump();
}

Future<void> _sendAndroidKey(WidgetTester tester, String type, int keyCode) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.keyEvent.name,
    SystemChannels.keyEvent.codec.encodeMessage({
      'type': type, 'keymap': 'android', 'keyCode': keyCode, 'scanCode': keyCode == 23 ? 353 : 0,
      'metaState': 0, 'flags': 0, 'source': 257, 'repeatCount': 0,
      'deviceId': -1, 'plainCodePoint': 0, 'codePoint': 0,
    }),
    (_) {},
  );
}
