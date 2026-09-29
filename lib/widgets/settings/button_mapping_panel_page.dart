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

import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Returned by the action picker to mean "unbind this trigger", which is
/// distinct from returning null for "the user backed out".
const _clearSentinel = Object();
const _clearAction = ButtonAction(type: ButtonActionType.block, label: "__clear__");

class ButtonMappingPanelPage extends StatefulWidget {
  static const String routeName = "button_mapping_panel";

  @override
  State<ButtonMappingPanelPage> createState() => _ButtonMappingPanelPageState();
}

class _ButtonMappingPanelPageState extends State<ButtonMappingPanelPage> with WidgetsBindingObserver {
  bool _mappingInProgress = false;

  Future<void> _runMappingFlow(Future<void> Function() flow) async {
    if (_mappingInProgress) return;
    setState(() => _mappingInProgress = true);
    try {
      await flow();
    } finally {
      if (mounted) setState(() => _mappingInProgress = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have just come back from the accessibility settings screen,
    // or from starting Shizuku.
    if (state == AppLifecycleState.resumed) {
      context.read<ButtonMappingService>()
        ..refreshServiceState()
        ..refreshRawInputStatus();
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<ButtonMappingService>(
        builder: (context, service, _) => Column(
          children: [
            Text("Button Mapping", style: Theme.of(context).textTheme.titleLarge),
            Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!service.serviceEnabled) _serviceDisabledNotice(context, service),
                    _sectionTitle(context, "Remote buttons"),
                    if (service.keyMappings.isEmpty)
                      _hint(context, "No buttons mapped yet.")
                    else
                      ...service.keyMappings.map((mapping) => _keyMappingTile(context, service, mapping)),
                    TextButton.icon(
                      icon: Icon(Icons.add),
                      label: Text("Map a button"),
                      onPressed: () => _runMappingFlow(() => _addKeyMapping(context, service)),
                    ),
                    _hint(
                      context,
                      "Select a mapped button to add a double press or long press action. "
                      "A mapped button stops doing what it normally did, including for the "
                      "presses you leave unbound.",
                    ),
                    Divider(),
                    _sectionTitle(context, "Firmware buttons"),
                    _rawInputSection(context, service),
                    Divider(),
                    _hint(
                      context,
                      "The Home and Power buttons are handled by Android before any app "
                      "sees them and cannot be remapped here. To use Home for FLauncher, "
                      "set FLauncher as your default launcher.",
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sectionTitle(BuildContext context, String title) => Padding(
        padding: EdgeInsets.only(top: 8, bottom: 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _hint(BuildContext context, String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );

  /// A shell input reader can observe buttons Android reserves for firmware.
  Widget _rawInputSection(BuildContext context, ButtonMappingService service) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hint(
            context,
            "Use this for Netflix, YouTube and other buttons that 'Map a button' "
            "cannot capture. The TV may also run the button's original action.",
          ),
          _hint(context, _rawInputStatusLine(service.rawInputStatus)),
          if (!service.rawInputStatus.ready) ...[
            if (service.rawInputStatus.shizuku == ShizukuStatus.permissionRequired)
              TextButton.icon(
                icon: Icon(Icons.lock_open),
                label: Text("Grant Shizuku permission"),
                onPressed: () => service.requestShizukuPermission(),
              ),
            _hint(
              context,
              service.rawInputStatus.pairingRequired
                  ? "If Wireless debugging is available in Developer options, pair with "
                      "the port and code Android shows. Some TVs also support ordinary "
                      "TCP debugging: run adb tcpip 5555 from a connected computer, then "
                      "press Connect and accept the prompt on the TV."
                  : "The debug bridge must be listening on TCP. Run this from a connected "
                      "computer after a reboot if needed:\n\n"
                      "    adb tcpip 5555\n\n"
                      "Then press Connect and accept the prompt on screen. Android remembers "
                      "FLauncher's key, but deliberately does not keep the TCP listener open "
                      "across reboots.",
            ),
            TextButton.icon(
              icon: Icon(Icons.link),
              label: Text("Connect"),
              onPressed: () => service.connectRawInput(),
            ),
            if (service.rawInputStatus.pairingRequired)
              TextButton.icon(
                icon: Icon(Icons.pin),
                label: Text("Pair with a code"),
                onPressed: () => _pairWithAdb(context, service),
              ),
          ],
          if (service.rawInputStatus.ready) ...[
            if (service.rawMappings.isEmpty)
              _hint(context, "No firmware buttons mapped yet.")
            else
              ...service.rawMappings.map((mapping) => _rawMappingTile(context, service, mapping)),
            TextButton.icon(
              icon: Icon(Icons.add),
              label: Text("Map a firmware button"),
              onPressed: () => _runMappingFlow(() => _addRawMapping(context, service)),
            ),
          ],
        ],
      );

  String _rawInputStatusLine(RawInputStatus status) {
    if (status.shizukuConnected) {
      return "Connected through Shizuku.";
    }
    if (status.shizuku == ShizukuStatus.ready && status.adb == AdbState.disconnected) {
      return "Shizuku permission granted; connect the input reader.";
    }
    switch (status.adb) {
      case AdbState.connected:
        return "Connected to this device's own debug bridge.";
      case AdbState.connecting:
        return "Connecting…";
      case AdbState.failed:
        return "Not connected: ${status.adbError ?? "unknown error"}";
      case AdbState.disconnected:
        return "Not connected.";
    }
  }

  Future<void> _pairWithAdb(BuildContext context, ButtonMappingService service) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AdbPairDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    final port = int.tryParse(result[0]);
    if (port == null) {
      return;
    }
    final paired = await service.pairWithAdb(port, result[1]);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          paired
              ? "Paired. Firmware buttons can be read now."
              : "Pairing failed. Check the port and code are the ones on screen, and that "
                  "the pairing dialog is still open.",
        ),
      ),
    );
  }

  Widget _rawMappingTile(BuildContext context, ButtonMappingService service, RawMapping mapping) =>
      Card(
        margin: EdgeInsets.only(bottom: 8),
        child: EnsureVisible(
          alignment: 0.5,
          child: ListTile(
            dense: true,
            title: Text(mapping.displayName, style: Theme.of(context).textTheme.bodyMedium),
            subtitle: Text(mapping.summary, style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              constraints: BoxConstraints(),
              splashRadius: 20,
              icon: Icon(Icons.delete_outline),
              onPressed: () => service.removeRawMapping(mapping),
            ),
            onTap: () => _editRawTriggers(context, service, mapping),
          ),
        ),
      );

  Future<void> _addRawMapping(BuildContext context, ButtonMappingService service) async {
    if (!service.serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Turn on the accessibility service first")),
      );
      return;
    }
    if (!service.rawInputStatus.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connect to the debug bridge first")),
      );
      return;
    }

    final captured = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CaptureKeyDialog(
        service: service,
        source: ButtonCaptureSource.raw,
      ),
    );
    if (captured == null || !mounted) {
      return;
    }
    final code = captured["rawCode"];
    debugPrint("Raw mapping capture returned: $captured; mounted=$mounted");
    if (code is! int || code < 0) {
      return;
    }

    final action = await _pickAction(context);
    if (action != null && !identical(action, _clearAction)) {
      await service.setRawAction(
        code: code,
        rawScanCode: captured["rawScanCode"] as int?,
        device: captured["device"] as String?,
        trigger: PressTrigger.single,
        action: action,
      );
    }
  }

  Future<void> _editRawTriggers(
    BuildContext context,
    ButtonMappingService service,
    RawMapping mapping,
  ) async {
    final trigger = await showDialog<PressTrigger>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(mapping.displayName),
        children: [
          for (final value in PressTrigger.values)
            _DialogOption(
              autofocus: value == PressTrigger.single,
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(
                "${value.label} — ${mapping.actionFor(value)?.description ?? "not set"}",
              ),
            ),
        ],
      ),
    );
    if (trigger == null || !mounted) {
      return;
    }

    final action = await _pickAction(context, allowClear: mapping.actionFor(trigger) != null);
    if (action == null) {
      return;
    }
    await service.setRawAction(
      code: mapping.code,
      rawScanCode: mapping.rawScanCode,
      device: mapping.device,
      trigger: trigger,
      action: identical(action, _clearAction) ? null : action,
    );
  }

  Widget _serviceDisabledNotice(BuildContext context, ButtonMappingService service) => Card(
        margin: EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text("Not active", style: Theme.of(context).textTheme.titleSmall),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                "Button mapping needs FLauncher's accessibility service turned on. "
                "Find it under Accessibility > Downloaded apps.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: 8),
              EnsureVisible(
                alignment: 0.5,
                child: OutlinedButton(
                  onPressed: () async {
                    if (await service.openAccessibilitySettings() || !mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "No settings screen answered. Open Settings > Accessibility yourself "
                          "and turn on FLauncher there.",
                        ),
                      ),
                    );
                  },
                  child: Text("Open accessibility settings"),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _keyMappingTile(BuildContext context, ButtonMappingService service, KeyMapping mapping) => Card(
        margin: EdgeInsets.only(bottom: 8),
        child: EnsureVisible(
          alignment: 0.5,
          child: ListTile(
            dense: true,
            isThreeLine: mapping.summary.contains("\n"),
            title: Text(mapping.displayName, style: Theme.of(context).textTheme.bodyMedium),
            subtitle: Text(mapping.summary, style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              constraints: BoxConstraints(),
              splashRadius: 20,
              icon: Icon(Icons.delete_outline),
              onPressed: () => service.removeKeyMapping(mapping),
            ),
            onTap: () => _editTriggers(context, service, mapping),
          ),
        ),
      );

  /// Lets the user bind single / double / long press on an existing button.
  Future<void> _editTriggers(
    BuildContext context,
    ButtonMappingService service,
    KeyMapping mapping,
  ) async {
    final trigger = await showDialog<PressTrigger>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(mapping.displayName),
        children: [
          for (final value in PressTrigger.values)
            _DialogOption(
              autofocus: value == PressTrigger.single,
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Text(
                "${value.label} — ${mapping.actionFor(value)?.description ?? "not set"}",
              ),
            ),
        ],
      ),
    );
    if (trigger == null || !mounted) {
      return;
    }

    final action = await _pickAction(context, allowClear: mapping.actionFor(trigger) != null);
    if (action == null) {
      return;
    }
    await service.setKeyAction(
      keyCode: mapping.keyCode,
      scanCode: mapping.scanCode,
      matchMode: mapping.matchMode,
      keyLabel: mapping.keyLabel,
      trigger: trigger,
      // _clearAction is the sentinel meaning "unbind this trigger".
      action: identical(action, _clearAction) ? null : action,
    );
  }

  Future<void> _addKeyMapping(BuildContext context, ButtonMappingService service) async {
    if (!service.serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Turn on the accessibility service first")),
      );
      return;
    }

    final captured = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CaptureKeyDialog(service: service),
    );
    if (captured == null || !mounted) {
      return;
    }

    final keyCode = captured["keyCode"] as int?;
    if (keyCode == null || keyCode < 0) {
      return;
    }
    final rawScanCode = captured["scanCode"];
    final scanCode = rawScanCode is int && rawScanCode != 0 ? rawScanCode : null;
    if (keyCode == 0 && scanCode == null) {
      // KEYCODE_UNKNOWN with no scan code either: nothing identifies this
      // button, so a binding on it would fire for every other such button.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("That button reports nothing this device can map")),
      );
      return;
    }

    final matchMode = await _pickKeyMatchMode(context, service, keyCode, scanCode);
    if (matchMode == null || !mounted) {
      return;
    }

    final action = await _pickAction(context);
    if (action != null && !identical(action, _clearAction)) {
      await service.setKeyAction(
        keyCode: keyCode,
        scanCode: scanCode,
        matchMode: matchMode,
        keyLabel: captured["keyLabel"] as String?,
        trigger: PressTrigger.single,
        action: action,
      );
    }
  }

  /// Key codes are the stable default. The scan-code option mirrors the
  /// troubleshooting path in established button mappers, but applies only to
  /// this binding so it cannot silently break every existing mapping.
  Future<KeyMatchMode?> _pickKeyMatchMode(
    BuildContext context,
    ButtonMappingService service,
    int keyCode,
    int? scanCode,
  ) async {
    if (keyCode == 0) return KeyMatchMode.scanCode;
    if (scanCode == null) return KeyMatchMode.keyCode;

    // Re-capturing the same physical button should edit its existing binding.
    for (final mapping in service.keyMappings) {
      if (mapping.keyCode == keyCode && mapping.scanCode == scanCode) {
        return mapping.matchMode;
      }
    }

    // Keep the common path one-step. Only ask about scan codes once the device
    // has demonstrated the ambiguity by reporting the same Android key code for
    // two different physical buttons.
    final hasCollision = service.keyMappings.any(
      (mapping) => mapping.keyCode == keyCode && mapping.scanCode != scanCode,
    );
    if (!hasCollision) return KeyMatchMode.keyCode;

    return showDialog<KeyMatchMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text("Identify this button by"),
        children: [
          _DialogOption(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(KeyMatchMode.scanCode),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Hardware scan code (recommended)"),
                Text(
                  "These two buttons report the same key code; use their scan "
                  "codes to tell them apart.",
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _DialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(KeyMatchMode.keyCode),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Android key code"),
                Text(
                  "Use one action for both buttons and replace the existing key-code mapping.",
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Asks what should happen when the button fires.
  ///
  /// Returns [_clearAction] when the user chose to unbind the trigger, and null
  /// when they backed out.
  Future<ButtonAction?> _pickAction(BuildContext context, {bool allowClear = false}) async {
    final type = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text("Run what?"),
        children: [
          _DialogOption(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.launchApp),
            child: Text("Open an app"),
          ),
          _DialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.openFlauncher),
            child: Text("Open FLauncher"),
          ),
          _DialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.openSettings),
            child: Text("Open Android settings"),
          ),
          _DialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.block),
            child: Text("Do nothing (block the button)"),
          ),
          if (allowClear)
            _DialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(_clearSentinel),
              child: Text("Remove this binding"),
            ),
        ],
      ),
    );

    if (type == null || !mounted) {
      return null;
    }
    if (type == _clearSentinel) {
      return _clearAction;
    }
    if (type is! ButtonActionType) {
      return null;
    }

    if (type != ButtonActionType.launchApp) {
      return ButtonAction(type: type);
    }

    final app = await _pickApplication(context, title: "Open which app?");
    if (app == null) {
      return null;
    }
    // Android refuses to start a disabled or absent app, so the binding is
    // saved but will do nothing until that is sorted out.
    if (mounted && !(app.installed && app.enabled)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            app.installed
                ? "${app.name} is disabled. Enable it in Android settings or the button will do nothing."
                : "${app.name} is not installed. Install it or the button will do nothing.",
          ),
        ),
      );
    }
    return ButtonAction(
      type: ButtonActionType.launchApp,
      packageName: app.packageName,
      label: app.name,
    );
  }

  Future<AppTarget?> _pickApplication(BuildContext context, {required String title}) async {
    final applications = await context.read<ButtonMappingService>().mappableApplications();
    if (!mounted || applications.isEmpty) {
      return null;
    }
    return showDialog<AppTarget>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: applications
            .asMap()
            .entries
            .map(
              (entry) => EnsureVisible(
                alignment: 0.5,
                child: _DialogOption(
                  autofocus: entry.key == 0,
                  onPressed: () => Navigator.of(dialogContext).pop(entry.value),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.value.name),
                      Text(
                        entry.value.status,
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

/// A [SimpleDialog] row that can take focus on its own.
///
/// [SimpleDialogOption] gained an `autofocus` parameter after the Flutter
/// version this app builds against, and without it the first row of a dialog
/// is unreachable with a remote until something else is focused first.
class _DialogOption extends StatelessWidget {
  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;

  const _DialogOption({
    required this.child,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        autofocus: autofocus,
        onTap: onPressed,
        child: Padding(
          // Matches SimpleDialogOption's own padding.
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
}

/// Collects the port and code Android shows under Wireless debugging > Pair
/// device with pairing code.
class _AdbPairDialog extends StatefulWidget {
  @override
  State<_AdbPairDialog> createState() => _AdbPairDialogState();
}

class _AdbPairDialogState extends State<_AdbPairDialog> {
  final _port = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text("Pair with this device"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "In Android settings open Developer options > Wireless debugging > "
              "Pair device with pairing code, and copy the two numbers here. Leave "
              "that screen open until pairing finishes.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 12),
            TextField(
              controller: _port,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Port"),
            ),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Pairing code"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop([_port.text.trim(), _code.text.trim()]),
            child: Text("Pair"),
          ),
        ],
      );
}

/// Waits for the user to press a button while the service swallows it.
class _CaptureKeyDialog extends StatefulWidget {
  final ButtonMappingService service;

  /// Android and `/dev/input` events share one native event channel, so every
  /// capture dialog must say which source it is learning.
  final ButtonCaptureSource source;

  const _CaptureKeyDialog({
    required this.service,
    this.source = ButtonCaptureSource.android,
  });

  @override
  State<_CaptureKeyDialog> createState() => _CaptureKeyDialogState();
}

class _CaptureKeyDialogState extends State<_CaptureKeyDialog> {
  static const _timeout = Duration(seconds: 10);
  late final ButtonCaptureSession _captureSession;
  Timer? _deadline;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _captureSession = widget.service.startKeyCapture(
      timeout: _timeout,
      source: widget.source,
    );
    // The dialog must remain escapable even if native cleanup never replies.
    _deadline = Timer(_timeout, () => _close(null));
    _capture();
  }

  @override
  void dispose() {
    _closed = true;
    _deadline?.cancel();
    _captureSession.cancel();
    super.dispose();
  }

  Future<void> _capture() async {
    final captured = await _captureSession.result;
    _close(captured);
  }

  void _close(Map<String, dynamic>? captured) {
    if (!mounted || _closed) return;
    _closed = true;
    _deadline?.cancel();
    _captureSession.cancel();
    final route = ModalRoute.of(context);
    debugPrint("Capture close: $captured; route=${route.runtimeType}; current=${route?.isCurrent}");
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(captured);
    } else {
      // Never pop a newer dialog from a stale capture completion.
      route.navigator?.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
        onWillPop: () async {
          _close(null);
          return false;
        },
        child: Focus(
          autofocus: true,
          onKey: (_, event) {
            if (event is RawKeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.gameButtonB)) {
              _close(null);
            }
            // A capture dialog owns focus. Repeats must not activate the mapping
            // button underneath it or play directional navigation sounds.
            return KeyEventResult.handled;
          },
          child: AlertDialog(
            title: Text("Press a button"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Press the remote button you want to map."),
                SizedBox(height: 8),
                Text(
                  widget.source == ButtonCaptureSource.raw
                      ? "Nothing within ${_timeout.inSeconds} seconds means the reader is not "
                          "seeing this remote. Check the status line on the previous screen."
                      : "If nothing happens within ${_timeout.inSeconds} seconds, that button "
                          "was not captured. Check accessibility, or try 'Map a firmware button'.",
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => _close(null), child: Text("Cancel")),
            ],
          ),
        ),
      );
}
