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

import 'dart:async';
import 'dart:ui' show WindowPadding;

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/settings/weather_panel_page.dart';
import 'package:flauncher/widgets/system_keyboard_dialog.dart';
import 'package:flauncher/widgets/tv_keyboard_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsService settings;
  late _WeatherService weather;

  setUp(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = const Size(1280, 720);
    binding.window.devicePixelRatioTestValue = 1;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
    SharedPreferences.setMockInitialValues({
      'weather_enabled': true,
      'weather_latitude': 10.0,
      'weather_longitude': 20.0,
      'weather_location_name': 'Saved place',
    });
    settings = SettingsService(await SharedPreferences.getInstance());
    weather = _WeatherService();
  });

  tearDown(() {
    settings.dispose();
    weather.dispose();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.clearPhysicalSizeTestValue();
    binding.window.clearDevicePixelRatioTestValue();
    binding.window.clearViewInsetsTestValue();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('City search opens installed IME and Search resolves the query once', (tester) async {
    weather.result = Future.value({'latitude': 51.5, 'longitude': -0.12});
    await _pumpWeather(tester, settings, weather);
    await _openCity(tester);
    expect(find.byType(TvKeyboardDialog), findsNothing);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.setClientArgs!['inputAction'], 'TextInputAction.search');

    await tester.enterText(find.byType(TextField), '  London  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsNothing);
    expect(weather.queries, ['London']);
    expect(settings.weatherLatitude, 51.5);
    expect(settings.weatherLongitude, -0.12);
    expect(settings.weatherLocationName, 'London');
  });

  testWidgets('Cancel and Back preserve draft and saved location', (tester) async {
    await _pumpWeather(tester, settings, weather);
    await _openCity(tester);
    await tester.enterText(find.byType(TextField), 'Cancelled city');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    await _openCity(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.enterText(find.byType(TextField), 'Back city');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _openCity(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    expect(weather.queries, isEmpty);
    expect(settings.weatherLatitude, 10);
    expect(settings.weatherLongitude, 20);
    expect(settings.weatherLocationName, 'Saved place');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });

  testWidgets('Remote OK opens the IME, reopens it, and D-pad reaches Cancel', (tester) async {
    await _pumpWeather(tester, settings, weather);
    Focus.of(tester.element(find.text('Search for city'))).requestFocus();
    await tester.pump();
    await _sendAndroidKey(tester, 'keydown', 23);
    await tester.pumpAndSettle();
    await _sendAndroidKey(tester, 'keyup', 23);
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(weather.queries, isEmpty);

    tester.testTextInput.hide();
    expect(tester.testTextInput.isVisible, isFalse);
    await _pressRemoteKey(tester, 23);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(weather.queries, isEmpty);
    await _pressRemoteKey(tester, 20);
    expect(Focus.of(tester.element(find.text('CANCEL'))).hasPrimaryFocus, isTrue);
    await _pressRemoteKey(tester, 23);
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsNothing);
  });

  testWidgets('Repeated activation has one dialog and one pending search', (tester) async {
    final result = Completer<Map<String, double>?>();
    weather.result = result.future;
    await _pumpWeather(tester, settings, weather);
    final edit = tester.widget<TextButton>(_cityButton).onPressed!;
    edit();
    edit();
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'London');
    await tester.pump();
    final submit = tester.widget<TextButton>(find.widgetWithText(TextButton, 'SEARCH')).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(weather.queries, ['London']);
    edit();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SystemKeyboardDialog), findsNothing);
    result.complete({'latitude': 51.5, 'longitude': -0.12});
    await tester.pumpAndSettle();
    expect(settings.weatherLocationName, 'London');
  });

  testWidgets('Android remote Back dismisses unsaved text', (tester) async {
    await _pumpWeather(tester, settings, weather);
    await _openCity(tester);
    await tester.enterText(find.byType(TextField), 'Back city');
    await _pressRemoteKey(tester, 4);
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsNothing);
    expect(weather.queries, isEmpty);
    expect(settings.weatherLocationName, 'Saved place');
    await _openCity(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });

  testWidgets('A stalled search times out and ignores its late coordinates', (tester) async {
    final result = Completer<Map<String, double>?>();
    weather.result = result.future;
    await _pumpWeather(tester, settings, weather);
    await _openCity(tester);
    await tester.enterText(find.byType(TextField), 'London');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(settings.weatherLocationName, 'Saved place');
    result.complete({'latitude': 51.5, 'longitude': -0.12});
    await tester.pumpAndSettle();
    expect(settings.weatherLatitude, 10);
    expect(settings.weatherLocationName, 'Saved place');
  });

  testWidgets('A search response after closing the page cannot change settings', (tester) async {
    final result = Completer<Map<String, double>?>();
    weather.result = result.future;
    await _pumpWeather(tester, settings, weather);
    await _openCity(tester);
    await tester.enterText(find.byType(TextField), 'London');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('Closed')));
    result.complete({'latitude': 51.5, 'longitude': -0.12});
    await tester.pumpAndSettle();
    expect(settings.weatherLocationName, 'Saved place');
    expect(settings.weatherLatitude, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IME resizing leaves the text field and actions without overflow', (tester) async {
    await _pumpWeather(tester, settings, weather);
    await _openCity(tester);
    tester.binding.window.viewInsetsTestValue = const _KeyboardInsets(500);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
  });

  testWidgets('Display name opens a prefilled system editor and Done saves only the name', (tester) async {
    await _pumpWeather(tester, settings, weather);
    await _openDisplayName(tester);
    expect(find.byType(TvKeyboardDialog), findsNothing);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.setClientArgs!['inputAction'], 'TextInputAction.done');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Saved place');
    await tester.enterText(find.byType(TextField), '  Home  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsNothing);
    expect(settings.weatherLocationName, 'Home');
    expect(settings.weatherLatitude, 10);
    expect(settings.weatherLongitude, 20);
    expect(settings.weatherEnabled, isTrue);
    expect(weather.queries, isEmpty);
  });

  testWidgets('Display name Cancel and Android Back preserve the saved text', (tester) async {
    await _pumpWeather(tester, settings, weather);
    await _openDisplayName(tester);
    await tester.enterText(find.byType(TextField), 'Cancelled name');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(settings.weatherLocationName, 'Saved place');
    await _openDisplayName(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Saved place');
    await tester.enterText(find.byType(TextField), 'Back name');
    await _pressRemoteKey(tester, 4);
    await tester.pumpAndSettle();
    expect(settings.weatherLocationName, 'Saved place');
    expect(settings.weatherLatitude, 10);
    expect(settings.weatherLongitude, 20);
    expect(weather.queries, isEmpty);
  });

  testWidgets('Display name Save allows clearing the name without clearing coordinates', (tester) async {
    await _pumpWeather(tester, settings, weather);
    await _openDisplayName(tester);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsNothing);
    expect(settings.weatherLocationName, isNull);
    expect(settings.weatherLatitude, 10);
    expect(settings.weatherLongitude, 20);
    expect(weather.queries, isEmpty);
  });

  testWidgets('Display name and city share a guard against overlapping editors', (tester) async {
    await _pumpWeather(tester, settings, weather);
    final editName = tester.widget<TextButton>(_displayNameButton).onPressed!;
    final editCity = tester.widget<TextButton>(_cityButton).onPressed!;
    editName();
    editName();
    editCity();
    await tester.pumpAndSettle();
    expect(find.byType(SystemKeyboardDialog), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Saved place');
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    await _openCity(tester);
    expect(find.byType(SystemKeyboardDialog), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(weather.queries, isEmpty);
  });
}

class _WeatherService extends WeatherService {
  final queries = <String>[];
  Future<Map<String, double>?> result = Future.value(null);

  @override
  Future<Map<String, double>?> geocodeCity(String city) {
    queries.add(city);
    return result;
  }
}

class _KeyboardInsets implements WindowPadding {
  const _KeyboardInsets(this.bottom);

  @override
  final double bottom;
  @override
  double get top => 0;
  @override
  double get left => 0;
  @override
  double get right => 0;
}

final _cityButton = find.widgetWithText(TextButton, 'Search for city');
final _displayNameButton = find.widgetWithText(TextButton, 'Location display name');

Future<void> _pumpWeather(WidgetTester tester, SettingsService settings, WeatherService weather) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<WeatherService>.value(value: weather),
    ],
    child: MaterialApp(
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      home: Scaffold(body: SizedBox(width: 350, child: WeatherPanelPage())),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openCity(WidgetTester tester) async {
  await tester.tap(_cityButton);
  await tester.pumpAndSettle();
}

Future<void> _openDisplayName(WidgetTester tester) async {
  await tester.tap(_displayNameButton);
  await tester.pumpAndSettle();
}

Future<void> _pressRemoteKey(WidgetTester tester, int keyCode) async {
  await _sendAndroidKey(tester, 'keydown', keyCode);
  await tester.pump();
  await _sendAndroidKey(tester, 'keyup', keyCode);
  await tester.pump();
}

Future<void> _sendAndroidKey(WidgetTester tester, String type, int keyCode) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.keyEvent.name,
    SystemChannels.keyEvent.codec.encodeMessage({
      'type': type, 'keymap': 'android', 'keyCode': keyCode, 'scanCode': keyCode == 23 ? 353 : 0,
      'metaState': 0, 'flags': 0, 'source': 257, 'repeatCount': 0,
      'deviceId': -1, 'plainCodePoint': 0, 'codePoint': 0,
    }),
    (_) {},
  );
}
