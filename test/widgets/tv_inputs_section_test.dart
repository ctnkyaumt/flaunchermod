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

import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/tv_inputs_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

const _methodChannel = MethodChannel('me.efesser.flauncher/method');
const _hdmiEventChannel = MethodChannel('me.efesser.flauncher/hdmi_event');
const _hdmiEventName = 'me.efesser.flauncher/hdmi_event';

const _service = 'com.mediatek.tvinput/.';
const _tuner = '${_service}tuner.TunerInputService/HW0';
const _av = '${_service}composite.CompositeInputService/HW1';
const _ypbpr = '${_service}component.ComponentInputService/HW2';
const _vga = '${_service}vga.VGAInputService/HW3';
const _hdmi2 = '${_service}hdmi.HDMIInputService/HW5';
const _hdmi4 = '${_service}hdmi.HDMIInputService/HW9';

Map<String, Object> _input(String id, String name, int type, String group) =>
    {'id': id, 'name': name, 'type': type, 'group': group};

// What the native catalog sends for the target Vestel/MediaTek TV.
final _hdmiInputs = [
  _input('${_service}hdmi.HDMIInputService/HW4', 'HDMI 1', 1007, 'hdmi'),
  _input(_hdmi2, 'HDMI 2', 1007, 'hdmi'),
  _input('${_service}hdmi.HDMIInputService/HW6', 'HDMI 3', 1007, 'hdmi'),
];
final _otherInputs = [
  _input(_tuner, 'TV', 0, 'other'),
  _input(_av, 'AV', 1001, 'other'),
  _input(_ypbpr, 'YPbPr', 1004, 'other'),
  _input(_vga, 'VGA', 1005, 'other'),
];

class _PageHandler implements PageNavigationHandler {
  final moves = <TraversalDirection>[];

  @override
  bool handlePageNavigation(TraversalDirection direction, FocusNode currentNode) {
    moves.add(direction);
    return false;
  }
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());
  // The event channel handler stays installed: the section cancels its stream on disposal.
  tearDown(() => _methodChannel.setMockMethodCallHandler(null));

  testWidgets('Shows an HDMI row and an Other row with the TV inputs in order', (tester) async {
    await _pump(tester, [..._hdmiInputs, ..._otherInputs]);

    expect(find.text('HDMI'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    for (final name in ['HDMI 1', 'HDMI 2', 'HDMI 3', 'TV', 'AV', 'YPbPr', 'VGA']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    double x(String name) => tester.getCenter(find.text(name)).dx;
    expect(x('HDMI 1') < x('HDMI 2') && x('HDMI 2') < x('HDMI 3'), isTrue);
    expect(x('TV') < x('AV') && x('AV') < x('YPbPr') && x('YPbPr') < x('VGA'), isTrue);
    expect(tester.getCenter(find.text('TV')).dy, greaterThan(tester.getCenter(find.text('HDMI 1')).dy));
    expect(find.byIcon(Icons.settings_input_hdmi), findsNWidgets(3));
    expect(find.byIcon(Icons.live_tv), findsOneWidget);
    expect(find.byIcon(Icons.settings_input_composite), findsOneWidget);
    expect(find.byIcon(Icons.settings_input_component), findsOneWidget);
    expect(find.byIcon(Icons.desktop_windows), findsOneWidget);
    _expectFocused(tester, 'HDMI 1');
  });

  testWidgets('OK on the AV card launches the composite input', (tester) async {
    final calls = await _pump(tester, [..._hdmiInputs, ..._otherInputs]);

    await _pressRemoteKey(tester, 20); // Down to the Other row
    await _pressRemoteKey(tester, 22); // Right from TV to AV
    _expectFocused(tester, 'AV');
    await _pressRemoteKey(tester, 23); // OK
    await tester.pump();

    final launches = calls.where((call) => call.method == 'launchTvInput').toList();
    expect(launches.length, 1);
    expect(launches.single.arguments, {'inputId': _av});
  });

  testWidgets('Tapping an HDMI card launches that HDMI input', (tester) async {
    final calls = await _pump(tester, [..._hdmiInputs, ..._otherInputs]);

    await tester.tap(find.text('HDMI 2'));
    await tester.pump();

    final launches = calls.where((call) => call.method == 'launchTvInput').toList();
    expect(launches.single.arguments, {'inputId': _hdmi2});
  });

  testWidgets('D-pad Down reaches the Other row and Up returns without changing page', (tester) async {
    final handler = _PageHandler();
    await _pump(tester, [..._hdmiInputs, ..._otherInputs], handler: handler);
    _expectFocused(tester, 'HDMI 1');

    await _pressRemoteKey(tester, 20);
    _expectFocused(tester, 'TV');
    await _pressRemoteKey(tester, 19);
    _expectFocused(tester, 'HDMI 1');
    expect(handler.moves, isEmpty);
  });

  testWidgets('No Other row when the TV has no other inputs', (tester) async {
    await _pump(tester, _hdmiInputs);

    expect(find.text('HDMI'), findsOneWidget);
    expect(find.text('HDMI 1'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('Without HDMI the empty notice shows and the first Other card is focused', (tester) async {
    await _pump(tester, _otherInputs);

    expect(find.text('No HDMI inputs detected.'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    _expectFocused(tester, 'TV');
  });

  testWidgets('Input events are routed by group and removal clears either row', (tester) async {
    await _pump(tester, [..._hdmiInputs, ..._otherInputs]);

    await _sendEvent(tester, {
      'action': 'INPUT_ADDED',
      'inputInfo': _input('${_service}scart.ScartInputService/HW8', 'SCART', 1003, 'other'),
    });
    await _sendEvent(tester, {
      'action': 'INPUT_ADDED',
      'inputInfo': _input(_hdmi4, 'HDMI 4', 1007, 'hdmi'),
    });
    expect(find.text('SCART'), findsOneWidget);
    expect(find.text('HDMI 4'), findsOneWidget);
    // SCART ranks after AV and before YPbPr, in the Other row.
    expect(tester.getCenter(find.text('SCART')).dx, greaterThan(tester.getCenter(find.text('AV')).dx));
    expect(tester.getCenter(find.text('SCART')).dx, lessThan(tester.getCenter(find.text('YPbPr')).dx));
    expect(tester.getCenter(find.text('SCART')).dy, tester.getCenter(find.text('AV')).dy);
    // HDMI 1 is focused and scaled, so compare with an unfocused HDMI card.
    expect(tester.getCenter(find.text('HDMI 4')).dy, tester.getCenter(find.text('HDMI 2')).dy);

    await _sendEvent(tester, {'action': 'INPUT_REMOVED', 'inputId': _vga});
    await _sendEvent(tester, {'action': 'INPUT_REMOVED', 'inputId': _hdmi4});
    expect(find.text('VGA'), findsNothing);
    expect(find.text('HDMI 4'), findsNothing);
    expect(find.text('HDMI 1'), findsOneWidget);
  });
}

/// Pumps the section with the native side mocked; returns the recorded method calls.
Future<List<MethodCall>> _pump(
  WidgetTester tester,
  List<Map<String, Object>> inputs, {
  PageNavigationHandler? handler,
}) async {
  tester.binding.window.physicalSizeTestValue = const Size(1280, 720);
  tester.binding.window.devicePixelRatioTestValue = 1.0;
  addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
  addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

  final calls = <MethodCall>[];
  _methodChannel.setMockMethodCallHandler((call) async {
    calls.add(call);
    switch (call.method) {
      case 'getTvInputs':
        return inputs;
      case 'launchTvInput':
        return true;
    }
    return null;
  });
  // The stream's listen/cancel requests; events are injected by the tests.
  _hdmiEventChannel.setMockMethodCallHandler((call) async => null);

  final settingsService = MockSettingsService();
  when(settingsService.appHighlightAnimationEnabled).thenReturn(false);
  await tester.pumpWidget(
    ChangeNotifierProvider<SettingsService>.value(
      value: settingsService,
      child: MaterialApp(
        // Same OK-key mapping as FLauncherApp.
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        },
        home: Material(
          child: FocusTraversalGroup(
            policy: PageAwareTraversalPolicy(handler ?? _PageHandler()),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [SizedBox(height: 150), TvInputsSection()],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

Future<void> _sendEvent(WidgetTester tester, Map<String, Object> event) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _hdmiEventName,
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void _expectFocused(WidgetTester tester, String label) =>
    expect(Focus.of(tester.element(find.text(label))).hasPrimaryFocus, isTrue, reason: '$label must own remote focus');

Future<void> _pressRemoteKey(WidgetTester tester, int keyCode) async {
  await _sendAndroidKey(tester, 'keydown', keyCode);
  await tester.pump();
  await _sendAndroidKey(tester, 'keyup', keyCode);
  await tester.pumpAndSettle();
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
