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

import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps confirmation, progress and errors on the same owned dialog route.
class DevicePowerDialog extends StatefulWidget {
  const DevicePowerDialog({Key? key, required this.channel, this.requestTimeout = const Duration(seconds: 10)})
      : super(key: key);

  final FLauncherChannel channel;
  final Duration requestTimeout;

  @override
  State<DevicePowerDialog> createState() => _DevicePowerDialogState();
}

class _DevicePowerDialogState extends State<DevicePowerDialog> {
  final _cancelFocus = FocusNode();
  bool _pending = false;
  bool _dismissed = false;
  String? _error;
  String _action = '';
  int _requestGeneration = 0;

  bool _isCurrentRequest(int generation) =>
      mounted && !_dismissed && generation == _requestGeneration && ModalRoute.of(context)?.isActive == true;

  void _dismiss() {
    final route = ModalRoute.of(context);
    if (_dismissed || route == null || !route.isActive) return;
    _dismissed = true;
    ++_requestGeneration;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
      // Flutter 3.7 does not complete a route's future when removing it.
      route.didComplete(null);
    }
  }

  Future<void> _requestPower({required bool standby}) async {
    if (_pending || _dismissed) return;
    final generation = ++_requestGeneration;
    setState(() {
      _pending = true;
      _error = null;
      _action = standby ? 'standby' : 'power menu';
    });
    // The selected power button disappears while waiting; keep Close reachable.
    _cancelFocus.requestFocus();

    String? error;
    try {
      final accepted = await (standby ? widget.channel.standbyDevice() : widget.channel.shutdownDevice())
          .timeout(widget.requestTimeout);
      if (!_isCurrentRequest(generation)) return;
      if (accepted) {
        // Acceptance is not proof that the device powered off. Never leave a
        // permanent spinner behind when the firmware ignores the request.
        _dismiss();
        return;
      }
      error = standby
          ? 'Standby is unavailable. Enable the button mapper or use the remote power button.'
          : 'The power menu is unavailable. Enable the button mapper or use the remote power button.';
    } on TimeoutException {
      error = 'The device did not respond. Try standby or the remote power button.';
    } on PlatformException catch (e) {
      error = e.message ?? 'The power request failed. Try the remote power button.';
    } catch (_) {
      error = 'The power request failed. Try the remote power button.';
    }
    if (!_isCurrentRequest(generation)) return;
    setState(() {
      _pending = false;
      _error = error;
    });
  }

  @override
  void dispose() {
    ++_requestGeneration;
    _cancelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        onKey: (_, event) {
          final androidBack = event.data is RawKeyEventDataAndroid &&
              (event.data as RawKeyEventDataAndroid).keyCode == 4;
          if (event is RawKeyDownEvent &&
              (androidBack || event.logicalKey == LogicalKeyboardKey.goBack ||
                  event.logicalKey == LogicalKeyboardKey.escape)) {
            _dismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: Text(_pending ? 'Requesting $_action' : _error == null ? 'Device power' : 'Power request failed'),
          content: _pending
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Waiting for the device...')],
                )
              : Text(_error ?? 'Choose standby to turn off the screen, or open the system power menu.'),
          actions: [
            TextButton(
              focusNode: _cancelFocus,
              autofocus: true,
              onPressed: _dismiss,
              child: Text(_pending ? 'CLOSE' : 'CANCEL'),
            ),
            if (!_pending) ...[
              TextButton(onPressed: () => _requestPower(standby: true), child: Text('STANDBY')),
              TextButton(onPressed: () => _requestPower(standby: false), child: Text('POWER MENU')),
            ],
          ],
        ),
      );
}
