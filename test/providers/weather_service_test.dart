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
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late SettingsService settings;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'weather_enabled': true,
      'weather_latitude': 10.0,
      'weather_longitude': 20.0,
      'weather_refresh_interval_minutes': 120,
    });
    preferences = await SharedPreferences.getInstance();
    settings = SettingsService(preferences);
  });

  tearDown(() => settings.dispose());

  WeatherService start(
    WidgetTester tester,
    WeatherJsonFetcher fetch, {
    Stream<dynamic>? network,
  }) =>
      WeatherService(
        preferences: preferences,
        networkAvailable: network,
        fetchJson: fetch,
        clock: () => tester.binding.clock.now(),
      )..settingsService = settings;

  double? shown(WidgetTester tester, WeatherService service) =>
      service.findCurrent(tester.binding.clock.now())?.temperature;

  // A request that never answers keeps its timeout timer until it fires.
  Future<void> stop(WidgetTester tester, List<WeatherService> services) async {
    for (final service in services) {
      service.dispose();
    }
    await tester.pump(const Duration(seconds: 16));
  }

  testWidgets('a restarted launcher shows the last forecast before the network answers', (tester) async {
    final now = tester.binding.clock.now();
    final first = start(tester, (_) async => _forecast(now, [21.5, 30]));
    await tester.pump();
    expect(shown(tester, first), 21.5);
    first.dispose();

    final restarted = start(tester, (_) => Completer<Map<String, dynamic>>().future);

    expect(shown(tester, restarted), 21.5);
    await stop(tester, [restarted]);
  });

  testWidgets('a forecast saved for another location is not shown', (tester) async {
    final now = tester.binding.clock.now();
    final first = start(tester, (_) async => _forecast(now, [21.5]));
    await tester.pump();
    first.dispose();
    await settings.setWeatherCoordinates(latitude: 50, longitude: 60);

    final restarted = start(tester, (_) => Completer<Map<String, dynamic>>().future);

    expect(shown(tester, restarted), isNull);
    await stop(tester, [restarted]);
  });

  testWidgets('a request that fails at startup is retried within seconds', (tester) async {
    final now = tester.binding.clock.now();
    var online = false;
    final service = start(tester, (_) async {
      if (!online) throw const SocketException('Network is unreachable');
      return _forecast(now, [18]);
    });
    await tester.pump();
    expect(shown(tester, service), isNull);

    online = true;
    await tester.pump(const Duration(seconds: 3));

    expect(shown(tester, service), 18);
    await stop(tester, [service]);
  });

  testWidgets('the forecast arrives as soon as the network is back', (tester) async {
    final now = tester.binding.clock.now();
    final network = StreamController<dynamic>();
    var online = false;
    final service = start(
      tester,
      (_) async {
        if (!online) throw const SocketException('Network is unreachable');
        return _forecast(now, [18]);
      },
      network: network.stream,
    );
    // Long enough offline that the next retry is many seconds away.
    await tester.pump(const Duration(seconds: 20));
    expect(shown(tester, service), isNull);

    online = true;
    network.add(true);
    await tester.pump(const Duration(milliseconds: 100));

    expect(shown(tester, service), 18);
    await stop(tester, [service]);
    // Not awaited: with its only listener gone the close never reports done.
    network.close();
  });

  testWidgets('a request that never answers gives way to one that does', (tester) async {
    final now = tester.binding.clock.now();
    var requests = 0;
    final service = start(tester, (_) {
      requests++;
      return requests == 1
          ? Completer<Map<String, dynamic>>().future
          : Future.value(_forecast(now, [12]));
    });

    await tester.pump(const Duration(seconds: 20));

    expect(shown(tester, service), 12);
    expect(service.fetching, isFalse);
    await stop(tester, [service]);
  });

  testWidgets('an answer for the previous location does not replace the new one', (tester) async {
    final now = tester.binding.clock.now();
    final previous = Completer<Map<String, dynamic>>();
    final service = start(
      tester,
      (url) => url.queryParameters['latitude'] == '10.0' ? previous.future : Future.value(_forecast(now, [35])),
    );
    await tester.pump();

    await settings.setWeatherCoordinates(latitude: 50, longitude: 60);
    await tester.pump();
    expect(shown(tester, service), 35);

    previous.complete(_forecast(now, [5]));
    await tester.pump();

    expect(shown(tester, service), 35);
    await stop(tester, [service]);
  });

  testWidgets('listeners hear about the next hour without a new request', (tester) async {
    final now = tester.binding.clock.now();
    final service = start(tester, (_) async => _forecast(now, [10, 20]));
    await tester.pump();
    expect(shown(tester, service), 10);
    final heard = <double?>[];
    service.addListener(() => heard.add(shown(tester, service)));

    await tester.pump(const Duration(minutes: 61));

    expect(heard, [20]);
    await stop(tester, [service]);
  });

  testWidgets('a forecast that ended hours ago is not shown as current', (tester) async {
    final now = tester.binding.clock.now();
    final service = start(tester, (_) async => _forecast(now.subtract(const Duration(hours: 3)), [9]));
    await tester.pump();

    expect(shown(tester, service), isNull);
    await stop(tester, [service]);
  });
}

/// An Open-Meteo hourly answer: one temperature per hour from [firstHour].
Map<String, dynamic> _forecast(DateTime firstHour, List<double> temperatures) => {
      'hourly': {
        'time': [
          for (var hour = 0; hour < temperatures.length; hour++)
            firstHour.add(Duration(hours: hour)).millisecondsSinceEpoch ~/ 1000,
        ],
        'temperature_2m': temperatures,
        'apparent_temperature': temperatures,
        'relativehumidity_2m': [for (var hour = 0; hour < temperatures.length; hour++) 50],
        'weathercode': [for (var hour = 0; hour < temperatures.length; hour++) 0],
      },
    };
