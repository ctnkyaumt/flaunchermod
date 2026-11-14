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

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The keys a TV remote, keyboard or gamepad uses for OK.
const remoteSelectKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

/// Whether [event] is OK (D-pad centre, Enter or gamepad A).
bool isRemoteSelect(RawKeyEvent event) => remoteSelectKeys.contains(event.logicalKey);

/// Whether [event] is Back in any of its forms: Flutter's goBack, Escape, or
/// Android's KEYCODE_BACK (4) whatever logical key it was mapped to.
bool isRemoteBack(RawKeyEvent event) {
  final key = event.logicalKey;
  final data = event.data;
  return key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.escape ||
      (data is RawKeyEventDataAndroid && data.keyCode == 4);
}

/// What a key event means for the physical button press it belongs to.
enum RemotePress {
  /// Not part of a press this tracker saw start: the release or auto-repeat
  /// of a press that went down before its owner existed (typically the press
  /// that opened the current route), or the release of a [held] press.
  /// Never an activation; pass the event on.
  none,

  /// The first key-down of a physical press.
  down,

  /// An auto-repeat of a press this tracker owns. Never an activation.
  repeat,

  /// The owned press has just been held for [RemotePressTracker.holdAfter].
  /// Reported once per press, which then ends without an [up].
  held,

  /// The release of an owned press that was not [held]: one per press.
  up,
}

// This package's language version predates constructor tear-offs.
DateTime _now() => DateTime.now();

class _Press {
  _Press(this.since);

  final DateTime since;
  bool held = false;
}

/// Turns raw key events into physical presses: each press yields one [RemotePress.down],
/// then [RemotePress.repeat]s, then either one [RemotePress.up] or (with [holdAfter]) one
/// [RemotePress.held]. A release or repeat whose key-down this tracker never saw yields
/// [RemotePress.none]. All forms of Back count as one key.
class RemotePressTracker {
  RemotePressTracker({this.holdAfter, DateTime Function()? clock}) : _clock = clock ?? _now;

  /// How long a press must last to be [RemotePress.held]; null never reports it.
  final Duration? holdAfter;
  final DateTime Function() _clock;
  final _presses = <Object, _Press>{};

  /// Whether a press this tracker saw go down has not been released yet.
  bool get isPressed => _presses.isNotEmpty;

  /// A key-down of [key]; [repeat] marks an auto-repeat sent while it is held.
  RemotePress keyDown(Object key, {bool repeat = false}) {
    if (!repeat) {
      _presses[key] = _Press(_clock());
      return RemotePress.down;
    }
    final press = _presses[key];
    if (press == null) {
      return RemotePress.none;
    }
    final holdAfter = this.holdAfter;
    if (!press.held && holdAfter != null && _clock().difference(press.since) >= holdAfter) {
      press.held = true;
      return RemotePress.held;
    }
    return RemotePress.repeat;
  }

  /// A key-up of [key].
  RemotePress keyUp(Object key) {
    final press = _presses.remove(key);
    if (press == null || press.held) {
      return RemotePress.none;
    }
    return RemotePress.up;
  }

  /// Feeds a Flutter key event. Android's own repeat count decides what is a
  /// repeat, as Flutter's keyboard state can miss a release sent elsewhere.
  RemotePress handle(RawKeyEvent event) {
    final Object key = isRemoteBack(event) ? LogicalKeyboardKey.goBack : event.logicalKey;
    if (event is RawKeyUpEvent) {
      return keyUp(key);
    }
    final data = event.data;
    return keyDown(key, repeat: data is RawKeyEventDataAndroid ? data.repeatCount > 0 : event.repeat);
  }

  /// Forgets every press in progress, e.g. when the app leaves the foreground.
  void reset() => _presses.clear();
}

/// A focusable [Focus] that calls [onSelect] once per physical OK press, on
/// its release. The release of a press that started elsewhere (such as the
/// one that opened this route) is passed on untouched.
class RemoteSelectFocus extends StatefulWidget {
  const RemoteSelectFocus({
    Key? key,
    required this.onSelect,
    required this.child,
    this.autofocus = false,
  }) : super(key: key);

  final VoidCallback onSelect;
  final Widget child;
  final bool autofocus;

  @override
  State<RemoteSelectFocus> createState() => _RemoteSelectFocusState();
}

class _RemoteSelectFocusState extends State<RemoteSelectFocus> {
  final _presses = RemotePressTracker();

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: widget.autofocus,
        canRequestFocus: true,
        onFocusChange: (focused) {
          if (!focused) _presses.reset();
        },
        onKey: (_, event) {
          if (!isRemoteSelect(event) || _presses.handle(event) != RemotePress.up) {
            return KeyEventResult.ignored;
          }
          widget.onSelect();
          return KeyEventResult.handled;
        },
        child: widget.child,
      );
}

/// For a dialog's [State]: runs one button action at a time and then closes
/// the dialog's route exactly once.
///
/// While an action runs, further activations (such as the auto-repeats of a
/// held OK) are ignored. When it is done the route is popped only if this
/// widget is still mounted and its route is still the current one. If the OK
/// press that started the action is still held, the pop waits for its release
/// so that the rest of the press cannot activate the screen underneath.
mixin RemoteRouteAction<T extends StatefulWidget> on State<T> {
  final _okPresses = RemotePressTracker();
  late final _RouteLifecycle _lifecycle = _RouteLifecycle(_onLifecycleChanged);
  bool _actionRunning = false;
  bool _closing = false;
  bool _closeOnRelease = false;
  Object? _closeResult;

  @override
  void initState() {
    super.initState();
    RawKeyboard.instance.addListener(_onRawKey);
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_onRawKey);
    WidgetsBinding.instance.removeObserver(_lifecycle);
    super.dispose();
  }

  /// Runs [action], unless one is already running or this route is closing,
  /// then closes this route with [result]. If [action] fails the route stays.
  Future<void> runThenClose(Future<void> Function() action, [Object? result]) async {
    if (_actionRunning || _closing) return;
    _actionRunning = true;
    try {
      await action();
    } finally {
      _actionRunning = false;
    }
    if (!mounted) return;
    _closing = true;
    _closeResult = result;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (foreground && _okPresses.isPressed) {
      _closeOnRelease = true;
    } else {
      _close();
    }
  }

  void _onRawKey(RawKeyEvent event) {
    if (!isRemoteSelect(event)) return;
    _okPresses.handle(event);
    if (_closeOnRelease && !_okPresses.isPressed) _close();
  }

  void _onLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    // The release goes to whatever took the foreground (e.g. a launched app).
    _okPresses.reset();
    if (_closeOnRelease) _close();
  }

  void _close() {
    _closeOnRelease = false;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    Navigator.of(context).pop(_closeResult);
  }
}

class _RouteLifecycle extends WidgetsBindingObserver {
  _RouteLifecycle(this._onChanged);

  final void Function(AppLifecycleState) _onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onChanged(state);
}
