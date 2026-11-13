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
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _savedForecastKey = "weather_forecast_cache";

/// Fetches one JSON document; replaced in tests.
typedef WeatherJsonFetcher = Future<Map<String, dynamic>> Function(Uri url);

class WeatherConditions {
  final DateTime time;
  final double temperature;
  final double apparentTemperature;
  final int humidity;
  final int weatherCode;

  WeatherConditions({
    required this.time,
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.weatherCode,
  });

  factory WeatherConditions.fromOpenMeteoHour(Map<String, dynamic> hourly, int index) {
    final timeSeconds = (hourly['time'] as List<dynamic>)[index] as num;
    return WeatherConditions(
      time: DateTime.fromMillisecondsSinceEpoch(timeSeconds.toInt() * 1000, isUtc: true).toLocal(),
      temperature: ((hourly['temperature_2m'] as List<dynamic>)[index] as num).toDouble(),
      apparentTemperature: ((hourly['apparent_temperature'] as List<dynamic>)[index] as num).toDouble(),
      humidity: ((hourly['relativehumidity_2m'] as List<dynamic>)[index] as num).toInt(),
      weatherCode: ((hourly['weathercode'] as List<dynamic>)[index] as num).toInt(),
    );
  }
}

class WeatherCache {
  final DateTime fetchedAt;
  final List<WeatherConditions> conditions;

  WeatherCache({required this.fetchedAt, required this.conditions});
}

/// What a forecast was asked for; a forecast is only shown for the same one.
class _WeatherQuery {
  final double latitude;
  final double longitude;
  final WeatherUnits units;

  const _WeatherQuery(this.latitude, this.longitude, this.units);

  String get unitsName => units == WeatherUnits.us ? 'us' : 'si';

  Uri get forecastUrl {
    final tempUnit = units == WeatherUnits.us ? 'fahrenheit' : 'celsius';
    return Uri.parse(
      'https://api.open-meteo.com/v1/forecast?'
      'latitude=$latitude&'
      'longitude=$longitude&'
      'hourly=temperature_2m&'
      'hourly=apparent_temperature&'
      'hourly=relativehumidity_2m&'
      'hourly=weathercode&'
      'timeformat=unixtime&'
      'temperature_unit=$tempUnit',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _WeatherQuery && other.latitude == latitude && other.longitude == longitude && other.units == units;

  @override
  int get hashCode => Object.hash(latitude, longitude, units);
}

class WeatherService extends ChangeNotifier {
  /// A request still unanswered after this long is given up on, so a
  /// connection that died mid-request cannot hold up every later refresh.
  static const requestTimeout = Duration(seconds: 15);

  /// Waits between attempts after a failure. The TV's clock is right before
  /// its Wi-Fi is up, so the first request after a cold boot usually fails.
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
  ];

  /// A request older than this when the network comes back was sent into a
  /// network that was not there yet.
  static const _restartAfter = Duration(seconds: 2);

  final SharedPreferences? _preferences;
  final WeatherJsonFetcher _fetchJson;
  final DateTime Function() _now;
  StreamSubscription<dynamic>? _networkSubscription;

  SettingsService? _settingsService;
  Timer? _refreshTimer;
  Timer? _retryTimer;
  bool _disposed = false;

  WeatherCache? _cache;
  _WeatherQuery? _cacheQuery;
  DateTime? _shownHour;

  _WeatherQuery? _lastQuery;
  _WeatherQuery? _inFlight;
  _WeatherQuery? _retryQuery;
  DateTime? _fetchStartedAt;
  int _generation = 0;
  int _failures = 0;
  bool _fetching = false;

  WeatherCache? get cache => _cache;
  bool get fetching => _fetching;

  /// [preferences] keeps the last forecast across restarts. [networkAvailable]
  /// emits whenever the device gets a usable network.
  WeatherService({
    SharedPreferences? preferences,
    Stream<dynamic>? networkAvailable,
    WeatherJsonFetcher? fetchJson,
    DateTime Function()? clock,
  })  : _preferences = preferences,
        _fetchJson = fetchJson ?? _httpGetJson,
        _now = clock ?? _systemNow {
    _networkSubscription = networkAvailable?.listen((_) => onNetworkAvailable(), onError: (Object _) {});
  }

  set settingsService(SettingsService settingsService) {
    if (identical(_settingsService, settingsService)) {
      return;
    }
    _settingsService?.removeListener(_maybeRefresh);
    _settingsService = settingsService;
    _settingsService?.addListener(_maybeRefresh);

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => refreshIfNeeded());

    _restoreSavedForecast();
    _maybeRefresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
    _networkSubscription?.cancel();
    _settingsService?.removeListener(_maybeRefresh);
    super.dispose();
  }

  /// Moves on to the next hour of the forecast and refetches a stale one.
  /// Called every minute and when the launcher returns to the foreground.
  void refreshIfNeeded() {
    if (_disposed) {
      return;
    }
    final hour = findCurrent(_now())?.time;
    if (hour != _shownHour) {
      _shownHour = hour;
      notifyListeners();
    }
    _maybeRefresh();
  }

  /// Fetches now instead of waiting out the retry delay.
  void onNetworkAvailable() {
    if (_disposed) {
      return;
    }
    _failures = 0;
    _cancelRetry();
    final startedAt = _fetchStartedAt;
    if (_inFlight != null && startedAt != null && _now().difference(startedAt) >= _restartAfter) {
      _abandonInFlight();
    }
    _maybeRefresh();
  }

  _WeatherQuery? _currentQuery() {
    final settings = _settingsService;
    if (settings == null || !settings.weatherEnabled) {
      return null;
    }
    final lat = settings.weatherLatitude;
    final lon = settings.weatherLongitude;
    if (lat == null || lon == null) {
      return null;
    }
    return _WeatherQuery(lat, lon, settings.weatherUnits);
  }

  void _maybeRefresh() {
    final settings = _settingsService;
    if (settings == null || _disposed) {
      return;
    }

    final query = _currentQuery();
    var changed = false;
    if (query != _lastQuery) {
      _lastQuery = query;
      _failures = 0;
      _cancelRetry();
    }
    // Another place's temperature under this place's name is worse than "-".
    if (_cache != null && _cacheQuery != query) {
      _setCache(null, null);
      changed = true;
    }
    if (_inFlight != null && _inFlight != query) {
      _abandonInFlight();
      changed = true;
    }
    if (query == null) {
      if (changed) notifyListeners();
      return;
    }

    final cache = _cache;
    var fresh = false;
    if (cache != null) {
      // A negative age means the clock was set back; the forecast is stale.
      final age = _now().difference(cache.fetchedAt);
      fresh = !age.isNegative && age < Duration(minutes: settings.weatherRefreshIntervalMinutes);
    }
    if (fresh || _inFlight != null || _retryQuery != null) {
      if (changed) notifyListeners();
      return;
    }

    _fetch(query);
  }

  Future<void> _fetch(_WeatherQuery query) async {
    final generation = ++_generation;
    _cancelRetry();
    _inFlight = query;
    _fetchStartedAt = _now();
    _fetching = true;
    notifyListeners();

    try {
      final body = await _fetchJson(query.forecastUrl).timeout(requestTimeout);
      if (generation != _generation) {
        return;
      }
      final hourly = body['hourly'] as Map<String, dynamic>;
      final fetchedAt = _now();
      _setCache(WeatherCache(fetchedAt: fetchedAt, conditions: _parseHourly(hourly)), query);
      _failures = 0;
      _saveForecast(query, fetchedAt, hourly);
    } catch (e) {
      if (generation != _generation) {
        return;
      }
      debugPrint('WeatherService: fetch failed - $e');
      _scheduleRetry(query);
    } finally {
      if (generation == _generation) {
        _inFlight = null;
        _fetching = false;
        notifyListeners();
      }
    }
  }

  void _scheduleRetry(_WeatherQuery query) {
    final delay = _retryDelays[_failures < _retryDelays.length ? _failures : _retryDelays.length - 1];
    _failures++;
    _retryQuery = query;
    _retryTimer = Timer(delay, () {
      _cancelRetry();
      _maybeRefresh();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryQuery = null;
  }

  /// Whatever the request in flight answers is no longer wanted.
  void _abandonInFlight() {
    _generation++;
    _inFlight = null;
    _fetching = false;
  }

  void _setCache(WeatherCache? cache, _WeatherQuery? query) {
    _cache = cache;
    _cacheQuery = query;
    _shownHour = findCurrent(_now())?.time;
  }

  List<WeatherConditions> _parseHourly(Map<String, dynamic> hourly) {
    final times = (hourly['time'] as List<dynamic>);
    final conditions = <WeatherConditions>[];
    for (var i = 0; i < times.length; i++) {
      conditions.add(WeatherConditions.fromOpenMeteoHour(hourly, i));
    }
    return conditions;
  }

  void _saveForecast(_WeatherQuery query, DateTime fetchedAt, Map<String, dynamic> hourly) {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }
    try {
      final saved = jsonEncode({
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'latitude': query.latitude,
        'longitude': query.longitude,
        'units': query.unitsName,
        'hourly': hourly,
      });
      preferences.setString(_savedForecastKey, saved).catchError((Object e) {
        debugPrint('WeatherService: forecast not saved - $e');
        return false;
      });
    } catch (e) {
      debugPrint('WeatherService: forecast not saved - $e');
    }
  }

  /// Shows the forecast from the previous run until a fresh one arrives.
  void _restoreSavedForecast() {
    final query = _currentQuery();
    final raw = _preferences?.getString(_savedForecastKey);
    if (query == null || raw == null || _cache != null) {
      return;
    }
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final savedFor = _WeatherQuery(
        (saved['latitude'] as num).toDouble(),
        (saved['longitude'] as num).toDouble(),
        saved['units'] == 'us' ? WeatherUnits.us : WeatherUnits.si,
      );
      if (savedFor != query) {
        return;
      }
      _setCache(
        WeatherCache(
          fetchedAt: DateTime.fromMillisecondsSinceEpoch((saved['fetchedAt'] as num).toInt()),
          conditions: _parseHourly(saved['hourly'] as Map<String, dynamic>),
        ),
        query,
      );
    } catch (e) {
      debugPrint('WeatherService: saved forecast unreadable - $e');
    }
  }

  WeatherConditions? findCurrent(DateTime now) {
    final conditions = _cache?.conditions;
    if (conditions == null || conditions.isEmpty) {
      return null;
    }

    for (var i = conditions.length - 1; i >= 0; i--) {
      if (!now.isBefore(conditions[i].time)) {
        // Each entry stands for one hour; past the last one nothing is known.
        if (i == conditions.length - 1 && now.difference(conditions[i].time) >= const Duration(hours: 1)) {
          return null;
        }
        return conditions[i];
      }
    }

    return null;
  }

  Future<Map<String, double>?> geocodeCity(String city) async {
    final query = Uri.encodeComponent(city);
    final url = Uri.parse('https://geocoding-api.open-meteo.com/v1/search?name=$query&count=1');
    final body = await _fetchJson(url);
    final results = body['results'];
    if (results is List && results.isNotEmpty) {
      final first = results.first as Map<String, dynamic>;
      final lat = (first['latitude'] as num).toDouble();
      final lon = (first['longitude'] as num).toDouble();
      return {'latitude': lat, 'longitude': lon};
    }
    return null;
  }
}

DateTime _systemNow() => DateTime.now();

Future<Map<String, dynamic>> _httpGetJson(Uri url) {
  final client = HttpClient()..connectionTimeout = WeatherService.requestTimeout;

  Future<Map<String, dynamic>> fetch() async {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }

    final responseBody = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(responseBody);
    return decoded as Map<String, dynamic>;
  }

  // Closing the client is what lets go of a connection that stopped answering.
  return fetch().timeout(WeatherService.requestTimeout).whenComplete(() => client.close(force: true));
}
