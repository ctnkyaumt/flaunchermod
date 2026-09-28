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

  testWidgets("button testing is available with accessibility and no raw reader", (tester) async {
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
    await tester.tap(find.text("Test remote buttons"));
    await tester.pumpAndSettle();
    expect(find.text("Press buttons on the remote"), findsOneWidget);
    expect(channel.captureModes, [true]);
    await tester.tap(find.text("Done"));
    await tester.pumpAndSettle();
    expect(channel.captureModes, [true, false]);
    await tester.pumpWidget(SizedBox());
    service.dispose();
    await channel.events.close();
  });
}

class _CaptureChannel extends FLauncherChannel {
  final events = StreamController<dynamic>.broadcast(sync: true);
  final captureModes = <bool>[];
  bool failNextArm = false;
  Future<void>? nextArm;
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
  }
}
