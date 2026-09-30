/*
 * FLaunchermod
 * Copyright (C)
 * 2026 - ctnkyaumt
 * Forked from: 2021  Étienne Fesser
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
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/widgets/settings/button_mapping_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const action = ButtonAction(type: ButtonActionType.openFlauncher);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ButtonMappingService> buildService(_CaptureChannel channel) async =>
      ButtonMappingService(await SharedPreferences.getInstance(), channel);

  group("KeyMapping identity", () {
    test("legacy known key mappings keep matching by key code", () {
      final mapping = KeyMapping.fromJson({
        "keyCode": 172,
        "scanCode": 314,
        "single": action.toJson(),
      });

      expect(mapping, isNotNull);
      final value = mapping!;
      expect(value.matchMode, KeyMatchMode.keyCode);
      expect(value.id, "kc:172");
    });

    test("legacy unknown key mappings keep matching by scan code", () {
      final mapping = KeyMapping.fromJson({
        "keyCode": 0,
        "scanCode": 314,
        "single": action.toJson(),
      });

      expect(mapping, isNotNull);
      final value = mapping!;
      expect(value.matchMode, KeyMatchMode.scanCode);
      expect(value.id, "sc:314");
    });

    test("a known key can explicitly use its hardware scan code", () {
      final mapping = KeyMapping.fromJson({
        "keyCode": 172,
        "scanCode": 314,
        "matchMode": "scanCode",
        "single": action.toJson(),
      });

      expect(mapping, isNotNull);
      final value = mapping!;
      expect(value.matchMode, KeyMatchMode.scanCode);
      expect(value.id, "sc:314");
      expect(value.toJson()["matchMode"], "scanCode");
    });

    test("a scan-code mapping without a scan code is rejected", () {
      final mapping = KeyMapping.fromJson({
        "keyCode": 172,
        "matchMode": "scanCode",
        "single": action.toJson(),
      });

      expect(mapping, isNull);
    });
  });

  group("capture source", () {
    final androidDown = <String, dynamic>{
      "keyAction": 0,
      "keyCode": 172,
      "rawCode": -1,
    };
    final rawDown = <String, dynamic>{
      "keyAction": 0,
      "keyCode": 0,
      "rawCode": 172,
    };

    test("normal mapping ignores raw events", () {
      expect(isButtonCaptureEvent(rawDown, ButtonCaptureSource.android), isFalse);
      expect(isButtonCaptureEvent(androidDown, ButtonCaptureSource.android), isTrue);
    });

    test("firmware mapping ignores Android events", () {
      expect(isButtonCaptureEvent(androidDown, ButtonCaptureSource.raw), isFalse);
      expect(isButtonCaptureEvent(rawDown, ButtonCaptureSource.raw), isTrue);
    });

    test("release events are never capture answers", () {
      expect(
        isButtonCaptureEvent({...androidDown, "keyAction": 1}, ButtonCaptureSource.any),
        isFalse,
      );
    });
  });

  group("raw input status", () {
    test("Shizuku permission alone is not reported as a live reader", () {
      final status = RawInputStatus.fromMap({
        "shizuku": "READY",
        "shizukuConnected": false,
        "adb": "DISCONNECTED",
      });

      expect(status.shizuku, ShizukuStatus.ready);
      expect(status.ready, isFalse);
    });

    test("a bound Shizuku reader is ready", () {
      final status = RawInputStatus.fromMap({
        "shizuku": "READY",
        "shizukuConnected": true,
        "adb": "DISCONNECTED",
      });

      expect(status.ready, isTrue);
    });
  });

  group("raw button identity", () {
    test("legacy codes and separate HID usages round-trip independently", () async {
      final channel = _CaptureChannel();
      final service = await buildService(channel);
      for (final usage in <int?>[null, 0, 0x000c00a5, 0x000c00a6]) {
        await service.setRawAction(
          code: 240,
          rawScanCode: usage,
          trigger: PressTrigger.single,
          action: action,
        );
      }

      expect(service.rawMappings.map((mapping) => mapping.id).toSet().length, 3);
      final restored = await buildService(channel);
      expect(restored.rawMappings.map((mapping) => mapping.rawScanCode),
          [null, 0x000c00a5, 0x000c00a6]);
      expect(restored.rawMappings[1].displayName, contains("0xc00a5"));

      await restored.removeRawMapping(restored.rawMappings[1]);
      expect(restored.rawMappings.map((mapping) => mapping.rawScanCode), [null, 0x000c00a6]);
      service.dispose();
      restored.dispose();
      await channel.events.close();
    });

    test("absent native HID usage has the same identity as a legacy code", () {
      const legacy = RawMapping(code: 240, single: action);
      final native = RawMapping.fromJson({
        "code": 240,
        "rawScanCode": 0,
        "single": action.toJson(),
      })!;
      expect(native.id, legacy.id);
      expect(native.rawScanCode, isNull);
      expect(native.displayName, legacy.displayName);
      expect(native.toJson().containsKey("rawScanCode"), isFalse);
    });
  });

  group("capture lifecycle", () {
    test("refresh completions after disposal do not notify a dead provider", () async {
      final enabled = Completer<bool>();
      final status = Completer<Map<dynamic, dynamic>>();
      final channel = _CaptureChannel()
        ..enabledReply = enabled.future
        ..statusReply = status.future;
      final service = await buildService(channel);
      final refreshEnabled = service.refreshServiceState();
      final refreshStatus = service.refreshRawInputStatus();

      service.dispose();
      enabled.complete(true);
      status.complete({"adb": "CONNECTED"});
      await Future.wait([refreshEnabled, refreshStatus]);

      expect(service.serviceEnabled, isFalse);
      expect(service.rawInputStatus.ready, isFalse);
      await channel.events.close();
    });

    test("cancelling removes the listener and immediately disarms capture", () async {
      final channel = _CaptureChannel();
      final service = await buildService(channel);
      final capture = service.startKeyCapture();
      await Future<void>.delayed(Duration.zero);
      expect(channel.events.hasListener, isTrue);

      await capture.cancel();

      expect(await capture.result, isNull);
      expect(channel.events.hasListener, isFalse);
      expect(channel.captureModes, [true, false]);
      service.dispose();
      await channel.events.close();
    });

    test("timeout cancels the underlying event subscription", () async {
      final channel = _CaptureChannel();
      final service = await buildService(channel);

      expect(await service.captureNextKey(timeout: Duration.zero), isNull);

      expect(channel.events.hasListener, isFalse);
      expect(channel.captureModes, [true, false]);
      service.dispose();
      await channel.events.close();
    });

    test("disposing the provider stops an active capture", () async {
      final channel = _CaptureChannel();
      final service = await buildService(channel);
      final capture = service.startKeyCapture();
      await Future<void>.delayed(Duration.zero);

      service.dispose();

      expect(await capture.result, isNull);
      expect(channel.events.hasListener, isFalse);
      expect(channel.captureModes, [true, false]);
      await channel.events.close();
    });

    test("arming failure releases the subscription and resolves the result", () async {
      final channel = _CaptureChannel()..failNextArm = true;
      final service = await buildService(channel);

      expect(await service.captureNextKey(), isNull);

      expect(channel.events.hasListener, isFalse);
      expect(channel.captureModes, [true, false]);
      service.dispose();
      await channel.events.close();
    });

    test("old dialog cancellation cannot disarm a replacement during slow setup", () async {
      final arm = Completer<void>();
      final channel = _CaptureChannel()..nextArm = arm.future;
      final service = await buildService(channel);
      final old = service.startKeyCapture();
      await Future<void>.delayed(Duration.zero);
      final current = service.startKeyCapture();

      arm.complete();
      expect(await old.result, isNull);
      await Future<void>.delayed(Duration.zero);
      await old.cancel();
      expect(channel.captureModes, [true, false, true]);

      final event = <String, dynamic>{"keyAction": 0, "keyCode": 172, "rawCode": -1};
      channel.events.add(event);
      expect(await current.result, event);
      expect(channel.captureModes, [true, false, true, false]);
      expect(channel.events.hasListener, isFalse);
      service.dispose();
      await channel.events.close();
    });
  });

  testWidgets("mapping panel omits diagnostic and app redirect sections", (tester) async {
    final channel = _CaptureChannel();
    final service = await buildService(channel);
    await service.refreshServiceState();
    await tester.pumpWidget(
      ChangeNotifierProvider<ButtonMappingService>.value(
        value: service,
        child: MaterialApp(home: Scaffold(body: ButtonMappingPanelPage())),
      ),
    );
    expect(service.rawInputStatus.ready, isFalse);
    expect(find.text("Test remote buttons"), findsNothing);
    expect(find.text("App shortcut buttons"), findsNothing);
    expect(find.text("Redirect an app button"), findsNothing);
    await tester.pumpWidget(SizedBox());
    service.dispose();
    await channel.events.close();
  });

  Future<void> showNestedMappingPanel(WidgetTester tester, ButtonMappingService service) async {
    await service.refreshServiceState();
    await service.refreshRawInputStatus();
    await tester.pumpWidget(
      ChangeNotifierProvider<ButtonMappingService>.value(
        value: service,
        child: MaterialApp(
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          },
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(body: ButtonMappingPanelPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> disposeMappingPanel(WidgetTester tester, ButtonMappingService service,
      _CaptureChannel channel) async {
    await tester.pumpWidget(SizedBox());
    service.dispose();
    await channel.events.close();
  }

  VoidCallback mappingStart(WidgetTester tester, String label) => tester.widget<TextButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        ),
      ).onPressed!;

  Future<void> sendAndroidKey(WidgetTester tester, String type, int keyCode,
      {int scanCode = 0}) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.keyEvent.name,
      SystemChannels.keyEvent.codec.encodeMessage({
        "type": type, "keymap": "android", "keyCode": keyCode, "scanCode": scanCode,
        "metaState": 0, "flags": 0, "source": 257, "repeatCount": 0,
        "deviceId": -1, "plainCodePoint": 0, "codePoint": 0,
      }),
      (_) {},
    );
  }

  testWidgets("repeated mapping activation opens one dialog and timeout keeps settings",
      (tester) async {
    final channel = _CaptureChannel();
    final service = await buildService(channel);
    await showNestedMappingPanel(tester, service);
    final start = mappingStart(tester, "Map a button");
    start();
    start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Press a button"), findsOneWidget);
    expect(channel.captureModes, [true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text("Press a button"), findsOneWidget);
    expect(channel.captureModes, [true]);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text("Press a button"), findsNothing);
    expect(find.text("Button Mapping"), findsOneWidget);
    expect(channel.captureModes, [true, false]);
    await disposeMappingPanel(tester, service, channel);
  });

  testWidgets("Back exits capture even while native cleanup is stalled", (tester) async {
    final cleanup = Completer<void>();
    final channel = _CaptureChannel()..nextDisarm = cleanup.future;
    final service = await buildService(channel);
    await showNestedMappingPanel(tester, service);
    mappingStart(tester, "Map a button")();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text("Press a button"), findsNothing);
    expect(find.text("Button Mapping"), findsOneWidget);
    cleanup.complete();
    await tester.pump();
    await disposeMappingPanel(tester, service, channel);
  });

  testWidgets("timeout beneath a newer route releases the mapping flow", (tester) async {
    final channel = _CaptureChannel();
    final service = await buildService(channel);
    await showNestedMappingPanel(tester, service);
    final start = mappingStart(tester, "Map a button");
    start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final navigator = Navigator.of(tester.element(find.byType(AlertDialog)));
    navigator.push<void>(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: Text("Newer page")),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text("Newer page"), findsOneWidget);
    expect(channel.captureModes, [true, false]);
    navigator.pop();
    await tester.pumpAndSettle();
    start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Press a button"), findsOneWidget);
    expect(channel.captureModes, [true, false, true]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await disposeMappingPanel(tester, service, channel);
  });

  testWidgets("Android Back key exits capture without a route-pop message", (tester) async {
    final channel = _CaptureChannel();
    final service = await buildService(channel);
    await showNestedMappingPanel(tester, service);
    mappingStart(tester, "Map a button")();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Flutter 3.7's test keyboard has no physical mapping for Android Back.
    // Send the wire event produced by a TV's KEYCODE_BACK instead.
    for (final type in ["keydown", "keyup"]) {
      await sendAndroidKey(tester, type, 4);
    }
    await tester.pumpAndSettle();
    expect(find.text("Press a button"), findsNothing);
    expect(find.text("Button Mapping"), findsOneWidget);
    expect(channel.captureModes, [true, false]);
    await disposeMappingPanel(tester, service, channel);
  });

  testWidgets("raw capture reaches action picker once and ignores reactivation", (tester) async {
    final channel = _CaptureChannel()
      ..statusReply = Future.value({"adb": "CONNECTED"});
    final service = await buildService(channel);
    await showNestedMappingPanel(tester, service);
    final start = mappingStart(tester, "Map a firmware button");
    start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    channel.events.add({
      "keyAction": 0, "keyCode": 0, "rawCode": 104,
      "rawScanCode": 295, "device": "/dev/input/event0",
    });
    await tester.pump();
    expect(find.text("Press a button"), findsOneWidget);
    channel.events.add({
      "keyAction": 1, "keyCode": 0, "rawCode": 104,
      "rawScanCode": 295, "device": "/dev/input/event0",
    });
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text("Run what?"), findsOneWidget);
    expect(find.text("Press a button"), findsNothing);
    start();
    await tester.pump();
    expect(find.text("Run what?"), findsOneWidget);
    expect(find.text("Press a button"), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text("Button Mapping"), findsOneWidget);
    expect(service.rawMappings, isEmpty);
    await disposeMappingPanel(tester, service, channel);
  });

  testWidgets("opening OK release leaves capture armed and the chooser untouched", (tester) async {
    final channel = _CaptureChannel()
      ..statusReply = Future.value({"adb": "CONNECTED"});
    final service = await buildService(channel);
    await showNestedMappingPanel(tester, service);
    Focus.of(tester.element(find.text("Map a firmware button"))).requestFocus();
    await tester.pump();
    await sendAndroidKey(tester, "keydown", 23, scanCode: 353);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Press a button"), findsOneWidget);
    expect(RawKeyboard.instance.keysPressed, contains(LogicalKeyboardKey.select));
    // Native filtering must forward this UP: its DOWN opened capture.
    await sendAndroidKey(tester, "keyup", 23, scanCode: 353);
    await tester.pump();
    expect(RawKeyboard.instance.keysPressed, isEmpty);
    expect(find.text("Press a button"), findsOneWidget);
    expect(channel.captureModes, [true]);
    final down = <String, dynamic>{
      "keyAction": 0, "keyCode": 0, "rawCode": 104,
      "rawScanCode": 295, "device": "/dev/input/event0",
    };
    channel.events.add(down);
    channel.events.add({...down, "keyAction": 1});
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Run what?"), findsOneWidget);
    expect(find.text("Open which app?"), findsNothing);
    expect(service.rawMappings, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await disposeMappingPanel(tester, service, channel);
  });

  test("raw Back cancellation does not become a mapping", () async {
    final channel = _CaptureChannel();
    final service = await buildService(channel);
    final capture = service.startKeyCapture(source: ButtonCaptureSource.raw);
    await Future<void>.delayed(Duration.zero);
    channel.events.add({"captureCancelled": true, "keyAction": 0, "rawCode": 158});
    expect(await capture.result, isNull);
    expect(channel.captureModes, [true, false]);
    service.dispose();
    await channel.events.close();
  });

  test("raw capture stays armed until the matching release", () async {
    final channel = _CaptureChannel();
    final service = await buildService(channel);
    final capture = service.startKeyCapture(source: ButtonCaptureSource.raw);
    await Future<void>.delayed(Duration.zero);
    final down = <String, dynamic>{
      "keyAction": 0, "rawCode": 240, "rawScanCode": 786597, "device": "remote",
    };
    channel.events.add(down);
    channel.events.add({"keyAction": 1, "rawCode": 240, "rawScanCode": 786551, "device": "remote"});
    await Future<void>.delayed(Duration.zero);
    expect(channel.captureModes, [true]);
    channel.events.add({...down, "keyAction": 1});
    expect(await capture.result, down);
    expect(channel.captureModes, [true, false]);
    service.dispose();
    await channel.events.close();
  });

  test("a raw button without release still completes", () async {
    final channel = _CaptureChannel();
    final service = await buildService(channel);
    final capture = service.startKeyCapture(source: ButtonCaptureSource.raw);
    await Future<void>.delayed(Duration.zero);
    final down = <String, dynamic>{"keyAction": 0, "rawCode": 104, "rawScanCode": 295};
    channel.events.add(down);
    expect(await capture.result, down);
    expect(channel.captureModes, [true, false]);
    service.dispose();
    await channel.events.close();
  });

  testWidgets("capture timeout closes its route while native cleanup is stalled", (tester) async {
    final cleanup = Completer<void>();
    final channel = _CaptureChannel()..nextDisarm = cleanup.future;
    final service = await buildService(channel);
    await showNestedMappingPanel(tester, service);
    mappingStart(tester, "Map a button")();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text("Press a button"), findsNothing);
    expect(find.text("Button Mapping"), findsOneWidget);
    cleanup.complete();
    await tester.pump();
    await disposeMappingPanel(tester, service, channel);
  });
}

class _CaptureChannel extends FLauncherChannel {
  final events = StreamController<dynamic>.broadcast(sync: true);
  final captureModes = <bool>[];
  bool failNextArm = false;
  Future<void>? nextArm;
  Future<void>? nextDisarm;
  Future<bool>? enabledReply;
  Future<Map<dynamic, dynamic>>? statusReply;

  @override
  Stream<dynamic> get keyCaptureStream => events.stream;

  @override
  Future<bool> isButtonMapperEnabled() => enabledReply ?? Future<bool>.value(true);

  @override
  Future<Map<dynamic, dynamic>> rawInputStatus() =>
      statusReply ?? Future<Map<dynamic, dynamic>>.value({});

  @override
  Future<void> notifyButtonMappingsChanged() async {}

  @override
  Future<void> setKeyCaptureMode(bool enabled) async {
    captureModes.add(enabled);
    if (enabled && failNextArm) {
      failNextArm = false;
      throw StateError("Capture unavailable");
    }
    if (enabled && nextArm != null) {
      final pending = nextArm;
      nextArm = null;
      await pending;
    }
    if (!enabled && nextDisarm != null) {
      final pending = nextDisarm;
      nextDisarm = null;
      await pending;
    }
  }
}
