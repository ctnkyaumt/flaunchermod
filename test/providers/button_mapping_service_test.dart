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

import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const action = ButtonAction(type: ButtonActionType.openFlauncher);

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
}
