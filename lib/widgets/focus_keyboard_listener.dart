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

import 'package:flauncher/widgets/remote_press.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const longPressableKeys = remoteSelectKeys;

class FocusKeyboardListener extends StatefulWidget {
  final WidgetBuilder builder;
  final KeyEventResult Function(LogicalKeyboardKey)? onPressed;
  final KeyEventResult Function(LogicalKeyboardKey)? onLongPress;

  FocusKeyboardListener({
    Key? key,
    required this.builder,
    this.onPressed,
    this.onLongPress,
  }) : super(key: key);

  @override
  _FocusKeyboardListenerState createState() => _FocusKeyboardListenerState();
}

class _FocusKeyboardListenerState extends State<FocusKeyboardListener> {
  final _presses = RemotePressTracker(holdAfter: const Duration(milliseconds: 500));

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        onKey: (_, rawKeyEvent) => _handleKey(rawKeyEvent),
        child: Builder(builder: widget.builder),
      );

  KeyEventResult _handleKey(RawKeyEvent event) {
    final key = event.logicalKey;
    if (!longPressableKeys.contains(key)) {
      // Other keys (arrows) act on every key-down, repeats included.
      if (event is RawKeyDownEvent) {
        return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
      }
      return KeyEventResult.ignored;
    }
    final press = _presses.handle(event);
    if (press == RemotePress.down) {
      return KeyEventResult.ignored;
    }
    if (press == RemotePress.held) {
      return widget.onLongPress?.call(key) ?? KeyEventResult.ignored;
    }
    if (press == RemotePress.up) {
      return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
    }
    // Repeats, owned or not, stay here; an unmatched release passes on.
    return event is RawKeyDownEvent ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}
