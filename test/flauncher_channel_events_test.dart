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

import 'dart:typed_data';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methodChannel = MethodChannel('me.efesser.flauncher/method');
const _packageEvents = 'me.efesser.flauncher/event';
const _tvInputEvents = 'me.efesser.flauncher/hdmi_event';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Answers the streams' listen/cancel requests; events are sent by the tests.
    for (final name in [_packageEvents, _tvInputEvents]) {
      MethodChannel(name).setMockMethodCallHandler((call) async => null);
    }
  });
  tearDown(() {
    _methodChannel.setMockMethodCallHandler(null);
    for (final name in [_packageEvents, _tvInputEvents]) {
      MethodChannel(name).setMockMethodCallHandler(null);
    }
  });

  /// Sends [events] as the native side would, then lets them reach the listeners.
  Future<void> send(String channel, List<Object?> events) async {
    await _settle();
    for (final event in events) {
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel,
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (_) {},
      );
    }
    await _settle();
  }

  Future<List<PackageEvent>> reportPackages(List<Object?> events) async {
    final received = <PackageEvent>[];
    FLauncherChannel().addPackageEventListener(received.add);
    await send(_packageEvents, events);
    return received;
  }

  test('an installed app arrives as a typed app with every field', () async {
    final received = await reportPackages([
      {
        'action': 'PACKAGE_ADDED',
        'activityInfo': {
          'packageName': 'new.app',
          'name': 'New app',
          'version': '1.2',
          'banner': Uint8List.fromList([1, 2, 3]),
          'icon': null,
          'sideloaded': true,
          'isSystemApp': false,
        },
      },
    ]);

    final event = received.single;
    expect(event.kind, PackageEventKind.added);
    final app = event.apps.single;
    expect(app.packageName, 'new.app');
    expect(app.name, 'New app');
    expect(app.version, '1.2');
    expect(app.banner, [1, 2, 3]);
    expect(app.icon, isNull);
    expect(app.sideloaded, isTrue);
    expect(app.isSystemApp, isFalse);
  });

  test('a removed package arrives with its package name', () async {
    final received = await reportPackages([
      {'action': 'PACKAGE_REMOVED', 'packageName': 'gone.app'},
    ]);

    expect(received.single.kind, PackageEventKind.removed);
    expect(received.single.removedPackageName, 'gone.app');
    expect(received.single.apps, isEmpty);
  });

  test('malformed package events are dropped before they reach the listener', () async {
    final received = await reportPackages([
      {'activityInfo': _app('no.action')},
      {'action': 'PACKAGE_ADDED', 'activityInfo': {'name': 'No package name'}},
      {'action': 'PACKAGE_CHANGED', 'activityInfo': null},
      {'action': 'PACKAGE_ADDED', 'activitiyInfo': _app('old.key')},
      {'action': 'PACKAGE_REMOVED'},
      {'action': 'PACKAGES_AVAILABLE', 'activitiesInfo': [null]},
      {'action': 'SOMETHING_ELSE', 'packageName': 'unknown.action'},
      'not a map',
      {'action': 'PACKAGE_CHANGED', 'activityInfo': _app('valid.app')},
    ]);

    expect(received.map((event) => event.kind), [PackageEventKind.changed]);
    expect(received.single.apps.map((app) => app.packageName), ['valid.app']);
  });

  test('a batch of available apps keeps the valid ones and drops a null entry', () async {
    final received = await reportPackages([
      {
        'action': 'PACKAGES_AVAILABLE',
        'activitiesInfo': [null, _app('sdcard.app'), {'packageName': 'nameless.app'}, _app('usb.app')],
      },
    ]);

    expect(received.single.kind, PackageEventKind.available);
    expect(received.single.apps.map((app) => app.packageName), ['sdcard.app', 'usb.app']);
  });

  test('the installed app list skips entries that are not apps', () async {
    _methodChannel.setMockMethodCallHandler((call) async {
      expect(call.method, 'getApplications');
      return [_app('first.app'), null, {'name': 'No package'}, _app('second.app')];
    });

    final apps = await FLauncherChannel().getInstalledApps();

    expect(apps.map((app) => app.packageName), ['first.app', 'second.app']);
    expect(apps.first.name, 'first.app name');
  });

  test('TV input events arrive typed and malformed ones are dropped', () async {
    final received = <TvInputEvent>[];
    final subscription = FLauncherChannel().tvInputEvents.listen(received.add);

    await send(_tvInputEvents, [
      {
        'action': 'INPUT_ADDED',
        'inputInfo': {'id': 'hdmi/HW5', 'name': 'HDMI 2', 'type': 1007, 'group': 'hdmi'},
      },
      {'action': 'INPUT_ADDED', 'inputInfo': {'name': 'No id'}},
      {'action': 'INPUT_REMOVED'},
      {'inputId': 'no/action'},
      {'action': 'INPUT_REMOVED', 'inputId': 'av/HW1'},
      {'action': 'INPUT_STATE_CHANGED', 'inputId': 'hdmi/HW5', 'state': 1},
    ]);
    await subscription.cancel();

    expect(received.map((event) => event.kind), [
      TvInputEventKind.added,
      TvInputEventKind.removed,
      TvInputEventKind.stateChanged,
    ]);
    final added = received[0].input!;
    expect([added.id, added.name, added.type, added.isHdmi], ['hdmi/HW5', 'HDMI 2', 1007, true]);
    expect(received[1].inputId, 'av/HW1');
    expect(received[2].inputId, 'hdmi/HW5');
    expect(received[2].state, 1);
  });

  test('the TV input list skips entries without an id', () async {
    _methodChannel.setMockMethodCallHandler((call) async => [
          {'id': 'av/HW1', 'name': 'AV', 'type': 1001, 'group': 'other'},
          {'name': 'No id', 'type': 1007, 'group': 'hdmi'},
          null,
        ]);

    final inputs = await FLauncherChannel().getTvInputs();

    expect(inputs.map((input) => [input.id, input.name, input.type, input.isHdmi]), [
      ['av/HW1', 'AV', 1001, false],
    ]);
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Object?> _app(String packageName) => {
      'packageName': packageName,
      'name': '$packageName name',
      'version': '1',
      'banner': null,
      'icon': null,
      'sideloaded': false,
      'isSystemApp': false,
    };
