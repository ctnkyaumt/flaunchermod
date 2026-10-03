/*
 * FLaunchermod
 * Copyright (C) 2021 Étienne Fesser
 * Copyright (C) 2026 ctnkyaumt
 * originally by efesser (30 May 2021)
 * ctnkyaumt 2026
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edits a city query through the device's installed keyboard.
class SystemKeyboardDialog extends StatefulWidget {
  const SystemKeyboardDialog({Key? key, required this.initialValue}) : super(key: key);

  final String initialValue;

  static Future<String?> show(BuildContext context, {required String initialValue}) => showDialog<String>(
        context: context,
        builder: (_) => SystemKeyboardDialog(initialValue: initialValue),
      );

  @override
  State<SystemKeyboardDialog> createState() => _SystemKeyboardDialogState();
}

class _SystemKeyboardDialogState extends State<SystemKeyboardDialog> {
  final _fieldFocus = FocusNode();
  final _activationKeys = <LogicalKeyboardKey>{};
  late final TextEditingController _controller;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _dismiss(String? result) {
    final route = ModalRoute.of(context);
    if (_dismissed || route?.isCurrent != true) return;
    _dismissed = true;
    _fieldFocus.unfocus();
    Navigator.of(context).pop(result);
  }

  void _submit([String? _]) {
    final query = _controller.text.trim();
    if (query.isNotEmpty) _dismiss(query);
  }

  KeyEventResult _onKey(FocusNode _, RawKeyEvent event) {
    final key = event.logicalKey;
    final data = event.data;
    final isBack = key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        (data is RawKeyEventDataAndroid && data.keyCode == 4);
    if (isBack) {
      if (event is RawKeyUpEvent) _dismiss(null);
      return KeyEventResult.handled;
    }
    if (_fieldFocus.hasFocus && key == LogicalKeyboardKey.arrowDown) {
      if (event is RawKeyDownEvent) FocusScope.of(context).nextFocus();
      return KeyEventResult.handled;
    }
    if (!_fieldFocus.hasFocus ||
        (key != LogicalKeyboardKey.select &&
            key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.gameButtonA)) {
      return KeyEventResult.ignored;
    }
    if (event is RawKeyDownEvent) {
      if (_activationKeys.add(key)) {
        // Android TV can keep the editor focused after dismissing its IME.
        // A fresh OK must reopen that installed keyboard, not submit the query.
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
      return KeyEventResult.handled;
    }
    if (event is RawKeyUpEvent && _activationKeys.remove(key)) return KeyEventResult.handled;
    // Let the unmatched release from the button opening this dialog pass.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        onKey: _onKey,
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          scrollable: true,
          title: const Text('Search for city'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: _controller,
              focusNode: _fieldFocus,
              autofocus: true,
              maxLines: 1,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'City or place'),
              onChanged: (_) => setState(() {}),
              onSubmitted: _submit,
            ),
          ),
          actions: [
            TextButton(onPressed: () => _dismiss(null), child: const Text('CANCEL')),
            TextButton(
              onPressed: _controller.text.trim().isEmpty ? null : _submit,
              child: const Text('SEARCH'),
            ),
          ],
        ),
      );
}
