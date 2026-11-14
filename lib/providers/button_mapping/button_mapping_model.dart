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

// The mapping model and the JSON shape of each entry. Pure Dart: no Flutter,
// no preferences. `ButtonMappingStore` on the native side reads the same JSON,
// so a change to any `toJson`/`fromJson` here must be matched there; the shared
// samples in test/fixtures/button_mappings/ are checked against both readers.

/// Same result as Flutter's `describeEnum`, without depending on Flutter.
String _enumName(Object value) {
  final description = value.toString();
  return description.substring(description.indexOf('.') + 1);
}

enum ButtonActionType {
  launchApp,
  openFlauncher,
  openSettings,
  block,
}

class ButtonAction {
  final ButtonActionType type;

  /// Only set when [type] is [ButtonActionType.launchApp].
  final String? packageName;

  /// Human-readable target, shown in the UI. Not read natively.
  final String? label;

  const ButtonAction({required this.type, this.packageName, this.label});

  Map<String, dynamic> toJson() => {
        "type": _enumName(type),
        if (packageName != null) "packageName": packageName,
        if (label != null) "label": label,
      };

  static ButtonAction? fromJson(Map<String, dynamic> json) {
    final type = ButtonActionType.values
        .cast<ButtonActionType?>()
        .firstWhere((value) => _enumName(value!) == json["type"], orElse: () => null);
    if (type == null) {
      return null;
    }
    return ButtonAction(
      type: type,
      packageName: json["packageName"] as String?,
      label: json["label"] as String?,
    );
  }

  String get description {
    switch (type) {
      case ButtonActionType.launchApp:
        return "Open ${label ?? packageName ?? "app"}";
      case ButtonActionType.openFlauncher:
        return "Open FLauncher";
      case ButtonActionType.openSettings:
        return "Open Android settings";
      case ButtonActionType.block:
        return "Do nothing";
    }
  }
}

/// How a button press is classified.
enum PressTrigger { single, doublePress, long }

extension PressTriggerLabel on PressTrigger {
  String get label {
    switch (this) {
      case PressTrigger.single:
        return "Single press";
      case PressTrigger.doublePress:
        return "Double press";
      case PressTrigger.long:
        return "Long press";
    }
  }
}

/// Which part of an Android `KeyEvent` identifies a mapped button.
///
/// Key codes are portable and remain the default. Some remotes collapse
/// several vendor buttons onto one Android key code, though; those buttons can
/// opt into their hardware scan code instead. Keeping this choice per mapping
/// avoids the all-or-nothing "use scan codes" switch used by other mappers.
enum KeyMatchMode { keyCode, scanCode }

/// Scan codes for remote buttons that report no usable key code.
///
/// Most TV remote extras come through as `KEYCODE_UNKNOWN`, so the scan code is
/// the only thing that tells them apart. Carried over from the earlier
/// button_mapping branch.
const _knownScanCodes = <int, String>{
  0x00000127: "Netflix",
  0x000c00a5: "YouTube",
  0x000c00a1: "Amazon Prime",
  0x000c0088: "Google Play",
  0x00070086: "Menu",
  0x000c0221: "Voice assistant",
};

/// A remote button and the actions bound to it.
class KeyMapping {
  final int keyCode;

  /// Hardware scan code, when the event carried one. It identifies unknown
  /// Android keys and can be selected explicitly when a remote reports one key
  /// code for several vendor buttons.
  final int? scanCode;

  final KeyMatchMode matchMode;

  /// Platform name for the key code, e.g. `KEYCODE_GUIDE`.
  final String? keyLabel;

  final ButtonAction? single;
  final ButtonAction? doublePress;
  final ButtonAction? long;

  const KeyMapping({
    required this.keyCode,
    this.scanCode,
    this.matchMode = KeyMatchMode.keyCode,
    this.keyLabel,
    this.single,
    this.doublePress,
    this.long,
  });

  bool get hasAny => single != null || doublePress != null || long != null;

  ButtonAction? actionFor(PressTrigger trigger) {
    switch (trigger) {
      case PressTrigger.single:
        return single;
      case PressTrigger.doublePress:
        return doublePress;
      case PressTrigger.long:
        return long;
    }
  }

  KeyMapping withAction(PressTrigger trigger, ButtonAction? action) => KeyMapping(
        keyCode: keyCode,
        scanCode: scanCode,
        matchMode: matchMode,
        keyLabel: keyLabel,
        single: trigger == PressTrigger.single ? action : single,
        doublePress: trigger == PressTrigger.doublePress ? action : doublePress,
        long: trigger == PressTrigger.long ? action : long,
      );

  /// Identity of the physical button, used to find an existing binding.
  ///
  /// Mirrors `ButtonMappingStore.Mappings.resolve` on the native side.
  String get id => matchMode == KeyMatchMode.scanCode ? "sc:$scanCode" : "kc:$keyCode";

  Map<String, dynamic> toJson() => {
        "keyCode": keyCode,
        if (scanCode != null) "scanCode": scanCode,
        "matchMode": _enumName(matchMode),
        if (keyLabel != null) "keyLabel": keyLabel,
        if (single != null) "single": single!.toJson(),
        if (doublePress != null) "double": doublePress!.toJson(),
        if (long != null) "long": long!.toJson(),
      };

  static KeyMapping? fromJson(Map<String, dynamic> json) {
    final keyCode = json["keyCode"];
    if (keyCode is! int) {
      return null;
    }
    ButtonAction? action(String key) {
      final raw = json[key];
      return raw is Map ? ButtonAction.fromJson(Map<String, dynamic>.from(raw)) : null;
    }

    final scanCode = json["scanCode"];
    final matchMode = json["matchMode"] == _enumName(KeyMatchMode.scanCode) ||
            // Existing mappings did not persist a mode. Preserve their old
            // behaviour: only KEYCODE_UNKNOWN fell back to the scan code.
            (!json.containsKey("matchMode") && keyCode == 0)
        ? KeyMatchMode.scanCode
        : KeyMatchMode.keyCode;
    if (matchMode == KeyMatchMode.scanCode && !(scanCode is int && scanCode != 0)) {
      return null;
    }

    final mapping = KeyMapping(
      keyCode: keyCode,
      scanCode: scanCode is int && scanCode != 0 ? scanCode : null,
      matchMode: matchMode,
      keyLabel: json["keyLabel"] as String?,
      single: action("single"),
      doublePress: action("double"),
      long: action("long"),
    );
    return mapping.hasAny ? mapping : null;
  }

  /// Friendly name for the button, falling back to the raw codes.
  String get displayName {
    final known = matchMode == KeyMatchMode.scanCode && scanCode != null
        ? _knownScanCodes[scanCode]
        : null;
    if (known != null) {
      return known;
    }

    final label = keyLabel;
    if (label != null && label.isNotEmpty && label != "KEYCODE_UNKNOWN") {
      // "KEYCODE_MEDIA_PLAY_PAUSE" -> "Media play pause"
      final stripped = label.startsWith("KEYCODE_") ? label.substring("KEYCODE_".length) : label;
      final words = stripped.replaceAll("_", " ").toLowerCase();
      if (words.isNotEmpty) {
        final friendly = "${words[0].toUpperCase()}${words.substring(1)}";
        return matchMode == KeyMatchMode.scanCode ? "$friendly (scan $scanCode)" : friendly;
      }
    }

    if (matchMode == KeyMatchMode.scanCode) {
      return "Button (scan $scanCode)";
    }
    return "Key $keyCode";
  }

  /// One-line summary of everything bound to this button.
  String get summary {
    final parts = <String>[
      for (final trigger in PressTrigger.values)
        if (actionFor(trigger) != null) "${trigger.label}: ${actionFor(trigger)!.description}",
    ];
    return parts.isEmpty ? "Nothing bound" : parts.join("\n");
  }
}

/// A button identified by its Linux key code, read straight off `/dev/input`.
///
/// This also covers buttons Android handles before dispatching to apps.
/// Reading them needs the shell input reader.
class RawMapping {
  final int code;

  /// HID usage reported in MSC_SCAN. Several vendor buttons may share code 240.
  final int? rawScanCode;

  /// The `/dev/input` node it came from, shown to help tell remotes apart.
  final String? device;

  final ButtonAction? single;
  final ButtonAction? doublePress;
  final ButtonAction? long;

  const RawMapping({
    required this.code,
    int? rawScanCode,
    this.device,
    this.single,
    this.doublePress,
    this.long,
  }) : rawScanCode = rawScanCode == 0 ? null : rawScanCode;

  bool get hasAny => single != null || doublePress != null || long != null;

  ButtonAction? actionFor(PressTrigger trigger) {
    switch (trigger) {
      case PressTrigger.single:
        return single;
      case PressTrigger.doublePress:
        return doublePress;
      case PressTrigger.long:
        return long;
    }
  }

  RawMapping withAction(PressTrigger trigger, ButtonAction? action) => RawMapping(
        code: code,
        rawScanCode: rawScanCode,
        device: device,
        single: trigger == PressTrigger.single ? action : single,
        doublePress: trigger == PressTrigger.doublePress ? action : doublePress,
        long: trigger == PressTrigger.long ? action : long,
      );

  Map<String, dynamic> toJson() => {
        "code": code,
        if (rawScanCode != null) "rawScanCode": rawScanCode,
        if (device != null) "device": device,
        if (single != null) "single": single!.toJson(),
        if (doublePress != null) "double": doublePress!.toJson(),
        if (long != null) "long": long!.toJson(),
      };

  static RawMapping? fromJson(Map<String, dynamic> json) {
    final code = json["code"];
    if (code is! int) {
      return null;
    }
    ButtonAction? action(String key) {
      final raw = json[key];
      return raw is Map ? ButtonAction.fromJson(Map<String, dynamic>.from(raw)) : null;
    }

    final mapping = RawMapping(
      code: code,
      rawScanCode: json["rawScanCode"] is int ? json["rawScanCode"] as int : null,
      device: json["device"] as String?,
      single: action("single"),
      doublePress: action("double"),
      long: action("long"),
    );
    return mapping.hasAny ? mapping : null;
  }

  String get id => rawScanCode == null ? "$code" : "$code:$rawScanCode";

  String get displayName => rawScanCode == null
      ? "Raw button $code"
      : "Raw button $code (usage 0x${rawScanCode!.toRadixString(16)})";

  String get summary {
    final parts = <String>[
      for (final trigger in PressTrigger.values)
        if (actionFor(trigger) != null) "${trigger.label}: ${actionFor(trigger)!.description}",
    ];
    return parts.isEmpty ? "Nothing bound" : parts.join("\n");
  }
}

/// Fallback for app shortcut buttons whose key events cannot be intercepted.
/// It redirects whenever the source app comes to the foreground, including
/// when the user opens that app without its remote button.
class AppRedirect {
  final String sourcePackage;

  /// Display name of the app the button normally opens.
  final String? sourceLabel;
  final ButtonAction action;

  const AppRedirect({required this.sourcePackage, this.sourceLabel, required this.action});

  Map<String, dynamic> toJson() => {
        "sourcePackage": sourcePackage,
        if (sourceLabel != null) "sourceLabel": sourceLabel,
        "action": action.toJson(),
      };

  static AppRedirect? fromJson(Map<String, dynamic> json) {
    final sourcePackage = json["sourcePackage"];
    if (sourcePackage is! String || sourcePackage.isEmpty) {
      return null;
    }
    final action = ButtonAction.fromJson(Map<String, dynamic>.from(json["action"] ?? {}));
    if (action == null) {
      return null;
    }
    return AppRedirect(
      sourcePackage: sourcePackage,
      sourceLabel: json["sourceLabel"] as String?,
      action: action,
    );
  }

  String get displayName => sourceLabel ?? sourcePackage;
}
