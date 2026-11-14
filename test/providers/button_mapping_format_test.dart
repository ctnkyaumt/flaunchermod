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

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/button_mapping/button_mapping_format.dart';
import 'package:flauncher/providers/button_mapping/button_mapping_model.dart';
import 'package:flauncher/providers/button_mapping_service.dart' show ButtonMappingService;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads a sample from test/fixtures/button_mappings/, looking upwards from the
/// working directory so it works from the project root or a subfolder. The same
/// files are read by ButtonMappingStoreTest.kt.
String fixture(String name) {
  final separator = Platform.pathSeparator;
  var dir = Directory.current.absolute;
  while (true) {
    final file = File(
        '${dir.path}${separator}test${separator}fixtures${separator}button_mappings$separator$name');
    if (file.existsSync()) return file.readAsStringSync();
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError("Sample button_mappings/$name not found above ${Directory.current.path}");
    }
    dir = parent;
  }
}

/// "type|packageName|label" of an action, or null when there is none.
String? act(ButtonAction? action) => action == null
    ? null
    : "${action.type.toString().split('.').last}|${action.packageName}|${action.label}";

List<KeyMapping> keysOf(String name) =>
    ButtonMappingFormat.decodeKeyMappings(ButtonMappingFormat.decodeRoot(fixture(name)));

List<RawMapping> rawsOf(String name) =>
    ButtonMappingFormat.decodeRawMappings(ButtonMappingFormat.decodeRoot(fixture(name)));

List<AppRedirect> redirectsOf(String name) =>
    ButtonMappingFormat.decodeAppRedirects(ButtonMappingFormat.decodeRoot(fixture(name)));

/// Decodes the sample and encodes it again; the result must be the sample.
void expectRoundTrip(String name) {
  final root = ButtonMappingFormat.decodeRoot(fixture(name));
  final encoded = ButtonMappingFormat.encode(
    keyMappings: ButtonMappingFormat.decodeKeyMappings(root),
    appRedirects: ButtonMappingFormat.decodeAppRedirects(root),
    rawMappings: ButtonMappingFormat.decodeRawMappings(root),
  );
  expect(jsonDecode(jsonEncode(encoded)), equals(jsonDecode(fixture(name))));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("shared sample: empty.json", () {
    test("decodes to three empty lists and encodes back to the same JSON", () {
      expect(keysOf("empty.json"), isEmpty);
      expect(redirectsOf("empty.json"), isEmpty);
      expect(rawsOf("empty.json"), isEmpty);
      expectRoundTrip("empty.json");
    });
  });

  group("shared sample: android_keys.json", () {
    test("reads key-code, unknown-key scan-code and explicit scan-code buttons", () {
      final keys = keysOf("android_keys.json");

      expect(keys.map((key) => key.id), ["kc:172", "sc:295", "sc:314"]);

      expect(keys[0].keyCode, 172);
      expect(keys[0].scanCode, isNull);
      expect(keys[0].matchMode, KeyMatchMode.keyCode);
      expect(keys[0].keyLabel, "KEYCODE_GUIDE");
      expect(act(keys[0].single), "launchApp|com.netflix.ninja|Netflix");
      expect(act(keys[0].doublePress), isNull);
      expect(act(keys[0].long), "openFlauncher|null|null");

      expect(keys[1].keyCode, 0);
      expect(keys[1].scanCode, 295);
      expect(keys[1].matchMode, KeyMatchMode.scanCode);
      expect(act(keys[1].single), isNull);
      expect(act(keys[1].doublePress), "openSettings|null|null");
      expect(keys[1].displayName, "Netflix");

      expect(keys[2].keyCode, 172);
      expect(keys[2].scanCode, 314);
      expect(keys[2].matchMode, KeyMatchMode.scanCode);
      expect(act(keys[2].single), "block|null|null");
    });

    test("encodes back to the same JSON", () => expectRoundTrip("android_keys.json"));
  });

  group("shared sample: raw_keys.json", () {
    test("reads raw buttons with and without HID usage and device", () {
      final raws = rawsOf("raw_keys.json");

      expect(raws.map((raw) => raw.id), ["240:786597", "240:786551", "116", "142"]);
      expect(raws.map((raw) => raw.code), [240, 240, 116, 142]);
      expect(raws.map((raw) => raw.rawScanCode), [786597, 786551, null, null]);
      expect(raws.map((raw) => raw.device), ["/dev/input/event3", null, "/dev/input/event2", null]);

      expect(act(raws[0].single), "openFlauncher|null|null");
      expect(act(raws[1].single), "openSettings|null|null");
      expect(act(raws[1].long), "block|null|null");
      expect(act(raws[2].doublePress), "launchApp|com.spotify.tv.android|Spotify");
      expect(act(raws[3].single), "block|null|null");
      expect(raws[0].displayName, "Raw button 240 (usage 0xc00a5)");
      expect(raws[3].displayName, "Raw button 142");
    });

    test("encodes back to the same JSON", () => expectRoundTrip("raw_keys.json"));
  });

  group("shared sample: app_redirects.json", () {
    test("reads redirects with and without a source label", () {
      final redirects = redirectsOf("app_redirects.json");

      expect(redirects.map((redirect) => redirect.sourcePackage),
          ["com.netflix.ninja", "com.google.android.youtube.tv"]);
      expect(redirects.map((redirect) => redirect.sourceLabel), ["Netflix", null]);
      expect(redirects.map((redirect) => redirect.displayName),
          ["Netflix", "com.google.android.youtube.tv"]);
      expect(act(redirects[0].action), "launchApp|com.plexapp.android|Plex");
      expect(act(redirects[1].action), "openFlauncher|null|null");
    });

    test("encodes back to the same JSON", () => expectRoundTrip("app_redirects.json"));
  });

  group("shared sample: legacy_key_mappings.json", () {
    test("entries saved without a match mode keep their old meaning", () {
      final keys = keysOf("legacy_key_mappings.json");

      expect(keys.map((key) => key.id), ["kc:172", "sc:314", "kc:23"]);
      expect(keys.map((key) => key.matchMode),
          [KeyMatchMode.keyCode, KeyMatchMode.scanCode, KeyMatchMode.keyCode]);
      expect(keys.map((key) => key.scanCode), [314, 314, null]);
      expect(act(keys[0].single), "openSettings|null|null");
      expect(act(keys[1].long), "block|null|null");
      expect(act(keys[2].single), "openFlauncher|null|null");
    });

    test("is saved again with an explicit match mode", () {
      final encoded = ButtonMappingFormat.encode(
        keyMappings: keysOf("legacy_key_mappings.json"),
        appRedirects: const [],
        rawMappings: const [],
      );

      expect(jsonDecode(jsonEncode(encoded["keyMappings"])), [
        {
          "keyCode": 172,
          "scanCode": 314,
          "matchMode": "keyCode",
          "single": {"type": "openSettings"},
        },
        {
          "keyCode": 0,
          "scanCode": 314,
          "matchMode": "scanCode",
          "keyLabel": "KEYCODE_UNKNOWN",
          "long": {"type": "block"},
        },
        {
          "keyCode": 23,
          "matchMode": "keyCode",
          "single": {"type": "openFlauncher"},
        },
      ]);
    });
  });

  group("shared sample: legacy_raw_mappings.json", () {
    test("code-only raw buttons have no HID usage", () {
      final raws = rawsOf("legacy_raw_mappings.json");

      expect(raws.map((raw) => raw.id), ["240", "116"]);
      expect(raws.map((raw) => raw.rawScanCode), [null, null]);
      expect(raws.map((raw) => raw.device), [null, "/dev/input/event2"]);
      expect(act(raws[0].single), "openSettings|null|null");
      expect(act(raws[1].long), "openFlauncher|null|null");
    });

    test("is saved again without a rawScanCode field", () {
      final encoded = ButtonMappingFormat.encode(
        keyMappings: const [],
        appRedirects: const [],
        rawMappings: rawsOf("legacy_raw_mappings.json"),
      );

      expect(jsonDecode(jsonEncode(encoded["rawMappings"])), [
        {
          "code": 240,
          "single": {"type": "openSettings"},
        },
        {
          "code": 116,
          "device": "/dev/input/event2",
          "long": {"type": "openFlauncher"},
        },
      ]);
    });
  });

  group("shared sample: legacy_app_redirects.json", () {
    test("a table with only redirects has no key or raw mappings", () {
      final root = ButtonMappingFormat.decodeRoot(fixture("legacy_app_redirects.json"));

      expect(root.containsKey("keyMappings"), isFalse);
      expect(ButtonMappingFormat.decodeKeyMappings(root), isEmpty);
      expect(ButtonMappingFormat.decodeRawMappings(root), isEmpty);
      final redirects = ButtonMappingFormat.decodeAppRedirects(root);
      expect(redirects.map((redirect) => redirect.sourcePackage), ["com.netflix.ninja"]);
      expect(redirects[0].sourceLabel, isNull);
      expect(act(redirects[0].action), "launchApp|com.plexapp.android|null");
    });
  });

  group("shared sample: dropped_entries.json", () {
    test("entries with no usable action or identity are skipped", () {
      expect(keysOf("dropped_entries.json").map((key) => key.id), ["kc:19"]);
      expect(redirectsOf("dropped_entries.json").map((redirect) => redirect.sourcePackage),
          ["com.example.ok"]);
      expect(rawsOf("dropped_entries.json").map((raw) => raw.id), ["97"]);
    });
  });

  group("ButtonMappingService on the shared samples", () {
    Future<ButtonMappingService> serviceWith(String sample) async {
      SharedPreferences.setMockInitialValues({"flutter.button_mappings": fixture(sample)});
      return ButtonMappingService(await SharedPreferences.getInstance(), _QuietChannel());
    }

    test("loads the saved table from preferences", () async {
      final service = await serviceWith("raw_keys.json");

      expect(service.rawMappings.map((raw) => raw.id), ["240:786597", "240:786551", "116", "142"]);
      expect(service.keyMappings, isEmpty);
      expect(service.appRedirects, isEmpty);
      service.dispose();
    });

    test("saves under the key and in the exact string the native side reads", () async {
      final service = await serviceWith("raw_keys.json");

      await service.removeRawMapping(service.rawMappings[3]);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString("button_mappings"),
        '{"keyMappings":[],"appRedirects":[],"rawMappings":['
        '{"code":240,"rawScanCode":786597,"device":"/dev/input/event3","single":{"type":"openFlauncher"}},'
        '{"code":240,"rawScanCode":786551,"single":{"type":"openSettings"},"long":{"type":"block"}},'
        '{"code":116,"device":"/dev/input/event2","double":{"type":"launchApp","packageName":"com.spotify.tv.android","label":"Spotify"}}'
        ']}',
      );
      service.dispose();
    });

    test("a table that is not a JSON object loads as empty", () async {
      SharedPreferences.setMockInitialValues({"flutter.button_mappings": "[1,2]"});
      final service =
          ButtonMappingService(await SharedPreferences.getInstance(), _QuietChannel());

      expect(service.keyMappings, isEmpty);
      expect(service.rawMappings, isEmpty);
      service.dispose();
    });
  });
}

class _QuietChannel extends FLauncherChannel {
  @override
  Future<bool> isButtonMapperEnabled() async => false;

  @override
  Future<Map<dynamic, dynamic>> rawInputStatus() async => {};

  @override
  Future<void> notifyButtonMappingsChanged() async {}
}
