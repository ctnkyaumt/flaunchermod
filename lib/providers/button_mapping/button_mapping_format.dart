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

import 'package:flauncher/providers/button_mapping/button_mapping_model.dart';

/// The whole mapping table as it is saved: one JSON object with the three
/// lists `keyMappings`, `appRedirects` and `rawMappings`.
///
/// Pure encode/decode, no preferences. The accessibility service reads the
/// same string natively (`ButtonMappingStore`), so the table is one JSON string
/// rather than a list: `shared_preferences` encodes lists with a prefix scheme
/// that is awkward to parse from Kotlin.
class ButtonMappingFormat {
  ButtonMappingFormat._();

  /// Parses the saved string. Throws when it is not a JSON object.
  static Map<String, dynamic> decodeRoot(String raw) => jsonDecode(raw) as Map<String, dynamic>;

  /// Entries that cannot be read are skipped, as are entries with no action.
  static List<KeyMapping> decodeKeyMappings(Map<String, dynamic> root) =>
      ((root["keyMappings"] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => KeyMapping.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<KeyMapping>()
          .toList();

  static List<AppRedirect> decodeAppRedirects(Map<String, dynamic> root) =>
      ((root["appRedirects"] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => AppRedirect.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<AppRedirect>()
          .toList();

  static List<RawMapping> decodeRawMappings(Map<String, dynamic> root) =>
      ((root["rawMappings"] as List?) ?? [])
          .whereType<Map>()
          .map((entry) => RawMapping.fromJson(Map<String, dynamic>.from(entry)))
          .whereType<RawMapping>()
          .toList();

  /// The object that is JSON-encoded into preferences and into backups.
  static Map<String, dynamic> encode({
    required List<KeyMapping> keyMappings,
    required List<AppRedirect> appRedirects,
    required List<RawMapping> rawMappings,
  }) =>
      {
        "keyMappings": keyMappings.map((mapping) => mapping.toJson()).toList(),
        "appRedirects": appRedirects.map((redirect) => redirect.toJson()).toList(),
        "rawMappings": rawMappings.map((mapping) => mapping.toJson()).toList(),
      };

  /// Strict check for tables coming from a backup file.
  static void validateBackup(Map<String, dynamic> data) {
    void validateAction(dynamic value) {
      if (value == null) return;
      if (value is! Map<String, dynamic> ||
          (value["packageName"] != null && value["packageName"] is! String) ||
          (value["label"] != null && value["label"] is! String)) {
        throw FormatException("Invalid button action");
      }
      final action = ButtonAction.fromJson(value);
      if (action == null ||
          (action.type == ButtonActionType.launchApp && (action.packageName?.isEmpty ?? true))) {
        throw FormatException("Invalid button action");
      }
    }

    for (final key in ["keyMappings", "appRedirects", "rawMappings"]) {
      final entries = data[key];
      if (entries is! List) throw FormatException("Missing button mapping list: $key");
      final identities = <String>{};
      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) throw FormatException("Invalid button mapping");
        for (final field in ["scanCode", "rawScanCode"]) {
          final value = entry[field];
          if (value != null && (value is! int || value < 0)) {
            throw FormatException("Invalid button scan code");
          }
        }
        for (final field in ["device", "keyLabel", "sourceLabel"]) {
          if (entry[field] != null && entry[field] is! String) {
            throw FormatException("Invalid button label");
          }
        }
        for (final field in ["single", "double", "long", "action"]) {
          validateAction(entry[field]);
        }
        String? identity;
        if (key == "keyMappings") {
          final code = entry["keyCode"];
          final mode = entry["matchMode"];
          if (code is! int || code < 0 || (mode != null && mode != "keyCode" && mode != "scanCode")) {
            throw FormatException("Invalid Android key mapping");
          }
          identity = KeyMapping.fromJson(entry)?.id;
        } else if (key == "rawMappings") {
          final code = entry["code"];
          if (code is! int || code < 0) throw FormatException("Invalid raw key mapping");
          identity = RawMapping.fromJson(entry)?.id;
        } else {
          identity = AppRedirect.fromJson(entry)?.sourcePackage;
        }
        if (identity == null || !identities.add(identity)) {
          throw FormatException("Invalid or duplicate button mapping");
        }
      }
    }
  }
}
