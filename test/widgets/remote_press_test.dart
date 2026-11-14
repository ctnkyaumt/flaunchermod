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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _ok = LogicalKeyboardKey.select;

void main() {
  test('a press of OK activates once, on its release', () {
    final presses = RemotePressTracker();

    expect(presses.keyDown(_ok), RemotePress.down);
    expect(presses.keyUp(_ok), RemotePress.up);
  });

  test('auto-repeats while OK is held never activate again', () {
    final presses = RemotePressTracker();

    final seen = [
      presses.keyDown(_ok),
      presses.keyDown(_ok, repeat: true),
      presses.keyDown(_ok, repeat: true),
      presses.keyDown(_ok, repeat: true),
      presses.keyUp(_ok),
    ];

    expect(seen, [RemotePress.down, RemotePress.repeat, RemotePress.repeat, RemotePress.repeat, RemotePress.up]);
  });

  test('holding OK past the long-press time is reported as held once, and its release does not activate', () {
    var now = DateTime(2026, 11, 14, 12);
    final presses = RemotePressTracker(holdAfter: const Duration(milliseconds: 500), clock: () => now);

    expect(presses.keyDown(_ok), RemotePress.down);
    now = DateTime(2026, 11, 14, 12, 0, 0, 200);
    expect(presses.keyDown(_ok, repeat: true), RemotePress.repeat);
    now = DateTime(2026, 11, 14, 12, 0, 0, 500);
    expect(presses.keyDown(_ok, repeat: true), RemotePress.held);
    now = DateTime(2026, 11, 14, 12, 0, 0, 900);
    expect(presses.keyDown(_ok, repeat: true), RemotePress.repeat);
    expect(presses.keyUp(_ok), RemotePress.none);
  });

  test('a short press still activates on release when long press is tracked', () {
    var now = DateTime(2026, 11, 14, 12);
    final presses = RemotePressTracker(holdAfter: const Duration(milliseconds: 500), clock: () => now);

    expect(presses.keyDown(_ok), RemotePress.down);
    now = DateTime(2026, 11, 14, 12, 0, 0, 100);
    expect(presses.keyDown(_ok, repeat: true), RemotePress.repeat);
    expect(presses.keyUp(_ok), RemotePress.up);
  });

  test('a release or repeat whose key-down was never seen does nothing', () {
    final presses = RemotePressTracker();

    // The press that opened this route went down before the route existed.
    expect(presses.keyDown(_ok, repeat: true), RemotePress.none);
    expect(presses.isPressed, isFalse);
    expect(presses.keyUp(_ok), RemotePress.none);
    // The next physical press is a normal one.
    expect(presses.keyDown(_ok), RemotePress.down);
    expect(presses.isPressed, isTrue);
    expect(presses.keyUp(_ok), RemotePress.up);
    expect(presses.isPressed, isFalse);
  });

  test('reset forgets a press in progress', () {
    final presses = RemotePressTracker();

    presses.keyDown(_ok);
    presses.reset();

    expect(presses.isPressed, isFalse);
    expect(presses.keyUp(_ok), RemotePress.none);
  });

  test('Back counts once per press whether it arrives as goBack or escape', () {
    final presses = RemotePressTracker();

    final seen = [
      // Android KEYCODE_BACK (goBack), held with repeats, released as escape.
      presses.handle(_androidDown(4)),
      presses.handle(_androidDown(4, repeatCount: 1)),
      presses.handle(_androidDown(111, repeatCount: 2)),
      presses.handle(_androidUp(111)),
      // A second press, as escape, released as goBack.
      presses.handle(_androidDown(111)),
      presses.handle(_androidUp(4)),
      // A Back release whose key-down this owner never saw.
      presses.handle(_androidUp(4)),
    ];

    expect(seen, [
      RemotePress.down,
      RemotePress.repeat,
      RemotePress.repeat,
      RemotePress.up,
      RemotePress.down,
      RemotePress.up,
      RemotePress.none,
    ]);
  });

  test('raw OK events from an Android remote follow the same rules', () {
    final presses = RemotePressTracker();

    final seen = [
      presses.handle(_androidUp(23)),
      presses.handle(_androidDown(23)),
      presses.handle(_androidDown(23, repeatCount: 1)),
      presses.handle(_androidUp(23)),
    ];

    expect(seen, [RemotePress.none, RemotePress.down, RemotePress.repeat, RemotePress.up]);
  });

  test('Back and OK are recognised in every key form', () {
    expect(isRemoteBack(_androidDown(4)), isTrue);
    expect(isRemoteBack(_androidDown(111)), isTrue);
    expect(isRemoteBack(_androidDown(23)), isFalse);
    expect(isRemoteSelect(_androidDown(23)), isTrue);
    expect(isRemoteSelect(_androidDown(66)), isTrue);
    expect(isRemoteSelect(_androidDown(4)), isFalse);
  });
}

RawKeyEvent _androidDown(int keyCode, {int repeatCount = 0}) =>
    RawKeyDownEvent(data: RawKeyEventDataAndroid(keyCode: keyCode, repeatCount: repeatCount));

RawKeyEvent _androidUp(int keyCode) => RawKeyUpEvent(data: RawKeyEventDataAndroid(keyCode: keyCode));
