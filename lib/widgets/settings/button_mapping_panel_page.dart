/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
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
    // The user may have just come back from the accessibility settings screen.
    if (state == AppLifecycleState.resumed) {
      context.read<ButtonMappingService>().refreshServiceState();
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
                      "send it somewhere else instead.",
                    ),
                    ...service.appRedirects.map((redirect) => _redirectTile(context, service, redirect)),
                    TextButton.icon(
                      icon: Icon(Icons.add),
                      label: Text("Redirect an app button"),
                      onPressed: () => _addAppRedirect(context, service),
                    ),
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
                  onPressed: service.openAccessibilitySettings,
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
            SimpleDialogOption(
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

  Future<void> _addAppRedirect(BuildContext context, ButtonMappingService service) async {
    final source = await _pickApplication(context, title: "Which app does the button open?");
    if (source == null || !mounted) {
      return;
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
          SimpleDialogOption(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.launchApp),
            child: Text("Open an app"),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.openFlauncher),
            child: Text("Open FLauncher"),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.openSettings),
            child: Text("Open Android settings"),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(ButtonActionType.block),
            child: Text("Do nothing (block the button)"),
          ),
          if (allowClear)
            SimpleDialogOption(
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
    return ButtonAction(
      type: ButtonActionType.launchApp,
      packageName: app.packageName,
      label: app.name,
    );
  }

  Future<App?> _pickApplication(BuildContext context, {required String title}) {
    final applications = context.read<AppsService>().applications;
    return showDialog<App>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: applications
            .asMap()
            .entries
            .map(
              (entry) => EnsureVisible(
                alignment: 0.5,
                child: SimpleDialogOption(
                  autofocus: entry.key == 0,
                  onPressed: () => Navigator.of(dialogContext).pop(entry.value),
                  child: Text(entry.value.name),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

/// Waits for the user to press a button while the service swallows it.
class _CaptureKeyDialog extends StatefulWidget {
  final ButtonMappingService service;

  const _CaptureKeyDialog({required this.service});

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
    final captured = await widget.service.captureNextKey(timeout: _timeout);
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
              "If nothing happens within ${_timeout.inSeconds} seconds, that button "
              "doesn't send a key press — use 'Redirect an app button' instead.",
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
