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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('me.efesser.flauncher/method');
  final launcher = FLauncherChannel();

  tearDown(() => channel.setMockMethodCallHandler(null));

  test('Search editor passes every option and decodes the submitted text', () async {
    MethodCall? received;
    channel.setMockMethodCallHandler((call) async {
      received = call;
      return 'Москва';
    });

    final text = await launcher.showSystemTextInput(
      title: 'Search for city', initialValue: 'Old city', fieldLabel: 'City or place',
      action: 'search', submitLabel: 'SEARCH', allowEmpty: false,
    );

    expect(text, 'Москва');
    expect(received!.method, 'showSystemTextInput');
    expect(received!.arguments, {
      'title': 'Search for city', 'initialValue': 'Old city', 'fieldLabel': 'City or place',
      'action': 'search', 'submitLabel': 'SEARCH', 'allowEmpty': false,
    });
  });

  test('Done editor retains a valid empty result', () async {
    channel.setMockMethodCallHandler((call) async {
      expect(call.arguments['action'], 'done');
      expect(call.arguments['allowEmpty'], isTrue);
      return '';
    });
    expect(await launcher.showSystemTextInput(
      title: 'Location display name', initialValue: '', fieldLabel: 'Name',
      action: 'done', submitLabel: 'SAVE', allowEmpty: true,
    ), '');
  });

  test('Editor result remains pending until native cancellation returns null', () async {
    final result = Completer<String?>();
    channel.setMockMethodCallHandler((_) => result.future);
    var finished = false;
    final editing = launcher.showSystemTextInput(
      title: 'Search for city', initialValue: '', fieldLabel: 'City or place',
      action: 'search', submitLabel: 'SEARCH', allowEmpty: false,
    ).then((value) {
      finished = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    result.complete(null);
    expect(await editing, isNull);
  });

  test('Native busy errors propagate without becoming empty text', () async {
    channel.setMockMethodCallHandler((_) async {
      throw PlatformException(code: 'busy', message: 'A text editor is already active');
    });
    await expectLater(launcher.showSystemTextInput(
      title: 'Search for city', initialValue: '', fieldLabel: 'City or place',
      action: 'search', submitLabel: 'SEARCH', allowEmpty: false,
    ), throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'busy')));
  });
}
