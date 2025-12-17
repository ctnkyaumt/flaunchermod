import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/foundation.dart';

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

class WeatherService extends ChangeNotifier {
  static const Duration cacheDuration = Duration(hours: 6);

  SettingsService? _settingsService;
  Timer? _refreshTimer;

  WeatherCache? _cache;
  bool _fetching = false;

  WeatherCache? get cache => _cache;
  bool get fetching => _fetching;

  set settingsService(SettingsService settingsService) {
    if (identical(_settingsService, settingsService)) {
      return;
    }
    _settingsService?.removeListener(_handleSettingsChanged);
    _settingsService = settingsService;
    _settingsService?.addListener(_handleSettingsChanged);

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _maybeRefresh());

    _maybeRefresh(force: true);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _settingsService?.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  Future<void> _handleSettingsChanged() async {
    await _maybeRefresh(force: true);
  }

  Future<void> _maybeRefresh({bool force = false}) async {
    final settings = _settingsService;
    if (settings == null) {
      return;
    }

    if (!settings.weatherEnabled) {
      if (_cache != null) {
        _cache = null;
        notifyListeners();
      }
      return;
    }

    final lat = settings.weatherLatitude;
    final lon = settings.weatherLongitude;
    if (lat == null || lon == null) {
      if (_cache != null) {
        _cache = null;
        notifyListeners();
      }
      return;
    }

    final shouldFetch =
        force || _cache == null || DateTime.now().difference(_cache!.fetchedAt) >= cacheDuration;

    if (!shouldFetch || _fetching) {
      return;
    }

    _fetching = true;
    notifyListeners();

    try {
      final conditions = await _fetchForecast(latitude: lat, longitude: lon, units: settings.weatherUnits);
      _cache = WeatherCache(fetchedAt: DateTime.now(), conditions: conditions);
    } catch (e) {
      debugPrint('WeatherService: fetch failed - $e');
    } finally {
      _fetching = false;
      notifyListeners();
    }
  }

  Future<List<WeatherConditions>> _fetchForecast({
    required double latitude,
    required double longitude,
    required WeatherUnits units,
  }) async {
    final tempUnit = units == WeatherUnits.us ? 'fahrenheit' : 'celsius';
    final url = Uri.parse(
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

    final body = await _httpGetJson(url);
    final hourly = (body['hourly'] as Map<String, dynamic>);
    final times = (hourly['time'] as List<dynamic>);

    final conditions = <WeatherConditions>[];
    for (var i = 0; i < times.length; i++) {
      conditions.add(WeatherConditions.fromOpenMeteoHour(hourly, i));
    }
    return conditions;
  }

  Future<Map<String, dynamic>> _httpGetJson(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody);
      return decoded as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  WeatherConditions? findCurrent(DateTime now) {
    final conditions = _cache?.conditions;
    if (conditions == null || conditions.isEmpty) {
      return null;
    }

    for (var i = conditions.length - 1; i >= 0; i--) {
      if (!now.isBefore(conditions[i].time)) {
        return conditions[i];
      }
    }

    return null;
  }

  Future<Map<String, double>?> geocodeCity(String city) async {
    final query = Uri.encodeComponent(city);
    final url = Uri.parse('https://geocoding-api.open-meteo.com/v1/search?name=$query&count=1');
    final body = await _httpGetJson(url);
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
