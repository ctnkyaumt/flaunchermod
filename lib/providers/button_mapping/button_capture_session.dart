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

import 'package:flutter/foundation.dart';

/// Which native input stream a capture dialog is waiting for.
///
/// Android and raw events are both broadcast while capture mode is armed. A
/// normal mapping must explicitly reject raw events, otherwise the faster
/// `/dev/input` reader can win the race and make a perfectly valid Android key
/// look unmappable.
enum ButtonCaptureSource { android, raw, any }

bool isButtonCaptureEvent(Map<dynamic, dynamic> event, ButtonCaptureSource source) {
  if (event["keyAction"] != 0) return false;
  final rawCode = event["rawCode"];
  final isRaw = rawCode is int && rawCode >= 0;
  switch (source) {
    case ButtonCaptureSource.android:
      return !isRaw;
    case ButtonCaptureSource.raw:
      return isRaw;
    case ButtonCaptureSource.any:
      return true;
  }
}

/// Owns one capture attempt so closing an old dialog cannot stop a newer one.
///
/// [_disarm] turns capture mode off again. [ButtonMappingService] builds the
/// session with a disarm that is a no-op once a newer session has replaced it,
/// then calls [start] exactly once.
class ButtonCaptureSession {
  final Future<void> Function() _disarm;
  final _result = Completer<Map<String, dynamic>?>();
  StreamSubscription<dynamic>? _subscription;
  Timer? _timeout;
  Timer? _rawReleaseTimeout;
  Map<String, dynamic>? _rawPress;
  bool _finished = false;

  ButtonCaptureSession(this._disarm);

  Future<Map<String, dynamic>?> get result => _result.future;

  void start(
    Stream<dynamic> events,
    Future<void> Function() arm,
    Duration timeout,
    ButtonCaptureSource source,
  ) async {
    try {
      _subscription = events.listen(
        (event) {
          if (_finished) return;
          if (event is Map && event["captureCancelled"] == true) {
            _finish(null);
          } else if (event is Map && _rawPress != null) {
            final pressed = _rawPress!;
            if (event["keyAction"] == 1 && event["rawCode"] == pressed["rawCode"] &&
                event["rawScanCode"] == pressed["rawScanCode"] &&
                event["device"] == pressed["device"]) {
              _finish(pressed);
            }
          } else if (event is Map && isButtonCaptureEvent(event, source)) {
            final pressed = Map<String, dynamic>.from(event);
            if (event["rawCode"] is int && event["rawCode"] >= 0) {
              // Keep interception armed until this press ends. Its Android
              // copy can otherwise activate the next dialog's focused option.
              _rawPress = pressed;
              // Some firmware never sends UP; still finish within half a second.
              _rawReleaseTimeout = Timer(const Duration(milliseconds: 500), () => _finish(pressed));
            } else {
              _finish(pressed);
            }
          }
        },
        onError: (Object error) => _finish(null),
        onDone: () => _finish(null),
      );
      _timeout = Timer(timeout, () => _finish(null));
      await arm();
    } catch (e) {
      await _finish(null);
    }
  }

  Future<void> cancel() => _finish(null);

  Future<void> _finish(Map<String, dynamic>? event) async {
    if (_finished) return;
    _finished = true;
    _timeout?.cancel();
    _rawReleaseTimeout?.cancel();
    // Queue disarming before waiting for stream cancellation. A replacement
    // capture can then queue its arm after this stop, even during slow setup.
    final disarming = _disarm().catchError((Object error) {
      debugPrint("ButtonMappingService: could not stop capture - $error");
    });
    // Unsubscribing from the platform stream must not hold up the result.
    // Disarming is serialized; any late event is rejected by _finished.
    _subscription?.cancel().catchError((Object error) {
      debugPrint("ButtonMappingService: could not cancel capture stream - $error");
    });
    await disarming;
    _result.complete(event);
  }
}
