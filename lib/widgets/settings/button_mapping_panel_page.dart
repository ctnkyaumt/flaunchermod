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
        ..refreshShizukuStatus();
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
                      onPressed: () => _addKeyMapping(context, service),
                    ),
                    _hint(
                      context,
                      "Select a mapped button to add a double press or long press action. "
                      "A mapped button stops doing what it normally did, including for the "
                      "presses you leave unbound.",
                    ),
                    Divider(),
                    _sectionTitle(context, "App shortcut buttons"),
                    _hint(
                      context,
                      "Netflix, YouTube and similar buttons open their app directly "
                      "without sending a key press. Pick the app the button opens to "
                      "send it somewhere else instead. Leave that app enabled — a "
                      "disabled app never opens, so there is no launch to catch.",
                    ),
                    ...service.appRedirects.map((redirect) => _redirectTile(context, service, redirect)),
                    TextButton.icon(
                      icon: Icon(Icons.add),
                      label: Text("Redirect an app button"),
                      onPressed: () => _addAppRedirect(context, service),
                    ),
                    Divider(),
                    _sectionTitle(context, "Firmware buttons"),
                    _shizukuSection(context, service),
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

  /// The Netflix and Prime buttons on most boxes never become key events at
  /// all, so nothing above can catch them. Reading the kernel input devices
  /// can, and that needs the shell privilege Shizuku hands out.
  Widget _shizukuSection(BuildContext context, ButtonMappingService service) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hint(
            context,
            "Buttons that print nothing in the button test are handled by the firmware "
            "and never reach an app. They can still be read straight from the kernel, "
            "which needs shell privilege. Disable the app the button opens first — this "
            "adds your action, it cannot take the original one away.",
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
                  ? "Otherwise, turn on Developer options > Wireless debugging, then pair "
                      "below with the port and code Android shows. Nothing else needs "
                      "installing."
                  : "Otherwise, adbd has to be listening on TCP. This device is too old for "
                      "wireless debugging, so run this once from a computer:\n\n"
                      "    adb tcpip 5555\n\n"
                      "Then press Connect and accept the prompt on screen. That is a one-off "
                      "— on the first successful connection FLauncher makes the setting "
                      "permanent, and reconnects on its own after every reboot.",
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
              onPressed: () => _addRawMapping(context, service),
            ),
            TextButton.icon(
              icon: Icon(Icons.bug_report_outlined),
              label: Text("Test remote buttons"),
              onPressed: () => _testButtons(context, service),
            ),
          ],
        ],
      );

  String _rawInputStatusLine(RawInputStatus status) {
    if (status.shizuku == ShizukuStatus.ready) {
      return "Connected through Shizuku.";
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
    if (!service.rawInputStatus.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connect to the debug bridge first")),
      );
      return;
    }

    final captured = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CaptureKeyDialog(service: service, rawOnly: true),
    );
    if (captured == null || !mounted) {
      return;
    }
    final code = captured["rawCode"];
    if (code is! int || code < 0) {
      return;
    }

    final action = await _pickAction(context);
    if (action != null && !identical(action, _clearAction)) {
      await service.setRawAction(
        code: code,
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
      keyLabel: mapping.keyLabel,
      trigger: trigger,
      // _clearAction is the sentinel meaning "unbind this trigger".
      action: identical(action, _clearAction) ? null : action,
    );
  }

  Widget _redirectTile(BuildContext context, ButtonMappingService service, AppRedirect redirect) => Card(
        margin: EdgeInsets.only(bottom: 8),
        child: EnsureVisible(
          alignment: 0.5,
          child: ListTile(
            dense: true,
            title: Text(redirect.displayName, style: Theme.of(context).textTheme.bodyMedium),
            subtitle: Text(redirect.action.description, style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              constraints: BoxConstraints(),
              splashRadius: 20,
              icon: Icon(Icons.delete_outline),
              onPressed: () => service.removeAppRedirect(redirect.sourcePackage),
            ),
            onTap: () async {
              final action = await _pickAction(context);
              if (action != null && !identical(action, _clearAction)) {
                await service.setAppRedirect(redirect.sourcePackage, redirect.sourceLabel, action);
              }
            },
          ),
        ),
      );

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

    final action = await _pickAction(context);
    if (action != null && !identical(action, _clearAction)) {
      await service.setKeyAction(
        keyCode: keyCode,
        scanCode: scanCode,
        keyLabel: captured["keyLabel"] as String?,
        trigger: PressTrigger.single,
        action: action,
      );
    }
  }

  Future<void> _testButtons(BuildContext context, ButtonMappingService service) async {
    if (!service.serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Turn on the accessibility service first")),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ButtonTestDialog(service: service),
    );
  }

  Future<void> _addAppRedirect(BuildContext context, ButtonMappingService service) async {
    final source = await _pickApplication(context, title: "Which app does the button open?");
    if (source == null || !mounted) {
      return;
    }
    // A redirect fires when the app comes to the foreground. A disabled app
    // never gets that far, so the button does nothing and there is nothing to
    // catch — the app has to be left enabled for this to work at all.
    if (source.installed && !source.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${source.name} is disabled, so its button opens nothing and there is no launch "
            "to redirect. Re-enable it in Android settings and this will take over instead.",
          ),
          duration: Duration(seconds: 8),
        ),
      );
    }
    final action = await _pickAction(context);
    if (action != null && !identical(action, _clearAction)) {
      await service.setAppRedirect(source.packageName, source.name, action);
    }
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

/// Lists every key event the accessibility service can see.
///
/// The point is to answer one question: does a given remote button reach an
/// app at all? Buttons the firmware handles internally — Home, Power, and on
/// many boxes the Netflix and Prime buttons — never show up here, and no
/// amount of mapping will catch them.
class _ButtonTestDialog extends StatefulWidget {
  final ButtonMappingService service;

  const _ButtonTestDialog({required this.service});

  @override
  State<_ButtonTestDialog> createState() => _ButtonTestDialogState();
}

class _ButtonTestDialogState extends State<_ButtonTestDialog> {
  final List<String> _lines = [];
  StreamSubscription<dynamic>? _subscription;
  Timer? _keepArmed;

  @override
  void initState() {
    super.initState();
    _subscription = widget.service.keyEvents.listen(_onEvent);
    widget.service.setCaptureMode(true);
    // The service disarms itself after 30s so a crashed dialog cannot leave the
    // remote dead; keep telling it we are still here.
    _keepArmed = Timer.periodic(
      Duration(seconds: 15),
      (_) => widget.service.setCaptureMode(true),
    );
  }

  @override
  void dispose() {
    _keepArmed?.cancel();
    _subscription?.cancel();
    widget.service.setCaptureMode(false);
    super.dispose();
  }

  void _onEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    final action = event["keyAction"] == 0 ? "down" : "up";
    final device = (event["device"] as String?) ?? "";
    final rawCode = event["rawCode"];
    final isRaw = rawCode is int && rawCode >= 0;
    setState(() {
      _lines.insert(
        0,
        isRaw
            ? "$action  raw code $rawCode  ($device)"
            : "$action  keyCode ${event["keyCode"]}  scanCode ${event["scanCode"]}"
                "${device.isEmpty ? "" : "  ($device)"}",
      );
      if (_lines.length > 40) {
        _lines.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text("Press buttons on the remote"),
        content: SizedBox(
          width: 520,
          height: 260,
          child: _lines.isEmpty
              ? Center(
                  child: Text(
                    "Nothing yet. A button that prints nothing here is handled by "
                    "the firmware and cannot be mapped by any app.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  itemCount: _lines.length,
                  itemBuilder: (_, index) => Text(
                    _lines[index],
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
        ),
        actions: [
          TextButton(
            // Deliberately not autofocused. The OK press that opened this
            // dialog repeats while held, and with Done under the cursor that
            // turned into an open/close loop. Back closes it; so does this,
            // once the user has moved to it.
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Done"),
          ),
        ],
      );
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

  /// Only accept events read off /dev/input, ignoring ordinary key events.
  /// A firmware button is being learned, and the remote's normal buttons would
  /// otherwise answer for it.
  final bool rawOnly;

  const _CaptureKeyDialog({required this.service, this.rawOnly = false});

  @override
  State<_CaptureKeyDialog> createState() => _CaptureKeyDialogState();
}

class _CaptureKeyDialogState extends State<_CaptureKeyDialog> {
  static const _timeout = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _capture();
  }

  Future<void> _capture() async {
    final captured = await widget.service.captureNextKey(
      timeout: _timeout,
      rawOnly: widget.rawOnly,
    );
    if (mounted) {
      Navigator.of(context).pop(captured);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text("Press a button"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Press the remote button you want to map."),
            SizedBox(height: 8),
            Text(
              widget.rawOnly
                  ? "Nothing within ${_timeout.inSeconds} seconds means the reader is not "
                      "seeing this remote. Check the status line on the previous screen."
                  : "If nothing happens within ${_timeout.inSeconds} seconds, that button "
                      "doesn't send a key press — try 'Map a firmware button' instead.",
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
