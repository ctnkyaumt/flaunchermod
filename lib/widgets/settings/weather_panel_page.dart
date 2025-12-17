import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class WeatherPanelPage extends StatefulWidget {
  static const String routeName = "weather_panel";

  @override
  State<WeatherPanelPage> createState() => _WeatherPanelPageState();
}

class _WeatherPanelPageState extends State<WeatherPanelPage> {
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();

  final FocusNode _latitudeFocus = FocusNode();
  final FocusNode _longitudeFocus = FocusNode();
  final FocusNode _displayNameFocus = FocusNode();

  bool _useCitySearch = true;
  bool _busy = false;

  bool _initializedFromSettings = false;

  @override
  void dispose() {
    _cityController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _displayNameController.dispose();

    _latitudeFocus.dispose();
    _longitudeFocus.dispose();
    _displayNameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    if (!_initializedFromSettings) {
      _displayNameController.text = settings.weatherLocationName ?? '';
      _latitudeController.text = settings.weatherLatitude?.toString() ?? '';
      _longitudeController.text = settings.weatherLongitude?.toString() ?? '';
      _initializedFromSettings = true;
    } else {
      if (!_displayNameFocus.hasFocus) {
        _displayNameController.text = settings.weatherLocationName ?? '';
      }
      if (!_latitudeFocus.hasFocus) {
        _latitudeController.text = settings.weatherLatitude?.toString() ?? '';
      }
      if (!_longitudeFocus.hasFocus) {
        _longitudeController.text = settings.weatherLongitude?.toString() ?? '';
      }
    }

    return Column(
      children: [
        Text("Weather", style: Theme.of(context).textTheme.titleLarge),
        Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 8),
          value: settings.weatherEnabled,
          onChanged: (value) => settings.setWeatherEnabled(value),
          title: Text("Enabled"),
          dense: true,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: IgnorePointer(
              ignoring: !settings.weatherEnabled || _busy,
              child: Opacity(
                opacity: !settings.weatherEnabled || _busy ? 0.6 : 1.0,
                child: Column(
                  children: [
                    _locationSection(context, settings),
                    const SizedBox(height: 16),
                    _optionsSection(settings),
                    const SizedBox(height: 16),
                    _dataAttribution(),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _locationSection(BuildContext context, SettingsService settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Location', style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        if (_useCitySearch) _citySearch(context, settings) else _coordinateInput(settings),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _useCitySearch = !_useCitySearch),
          child: Text(_useCitySearch ? 'Enter coordinates' : 'Search for city'),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            focusNode: _displayNameFocus,
            controller: _displayNameController,
            decoration: const InputDecoration(labelText: 'Location display name', isDense: true),
            onSubmitted: (value) => settings.setWeatherLocationName(value),
          ),
        ),
      ],
    );
  }

  Widget _citySearch(BuildContext context, SettingsService settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FocusKeyboardListener(
        onPressed: (key) {
          if (key == LogicalKeyboardKey.arrowDown) {
            FocusScope.of(context).nextFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            FocusScope.of(context).previousFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        builder: (context) => Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cityController,
                decoration: const InputDecoration(labelText: 'Search for city', isDense: true),
                keyboardType: TextInputType.text,
                onSubmitted: (value) => _applyCity(context, settings, value),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _applyCity(context, settings, _cityController.text),
              child: const Icon(Icons.search),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coordinateInput(SettingsService settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              focusNode: _latitudeFocus,
              controller: _latitudeController,
              decoration: const InputDecoration(labelText: 'Latitude', isDense: true),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _applyCoordinates(settings),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              focusNode: _longitudeFocus,
              controller: _longitudeController,
              decoration: const InputDecoration(labelText: 'Longitude', isDense: true),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _applyCoordinates(settings),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyCity(BuildContext context, SettingsService settings, String city) async {
    final trimmed = city.trim();
    if (trimmed.isEmpty) {
      return;
    }

    setState(() => _busy = true);
    try {
      final coords = await context.read<WeatherService>().geocodeCity(trimmed);
      if (coords == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to find location. Please try again.')),
        );
        return;
      }

      await settings.setWeatherCoordinates(latitude: coords['latitude'], longitude: coords['longitude']);
      await settings.setWeatherLocationName(trimmed);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot determine location: $e')),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _applyCoordinates(SettingsService settings) async {
    final lat = double.tryParse(_latitudeController.text.trim());
    final lon = double.tryParse(_longitudeController.text.trim());
    await settings.setWeatherCoordinates(latitude: lat, longitude: lon);
  }

  Widget _optionsSection(SettingsService settings) {
    return Column(
      children: [
        const Divider(),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          value: settings.weatherShowDetails,
          onChanged: (value) => settings.setWeatherShowDetails(value),
          title: const Text('Show extended details'),
          dense: true,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          value: settings.weatherShowCity,
          onChanged: (value) => settings.setWeatherShowCity(value),
          title: const Text('Show city display name'),
          dense: true,
        ),
        const Divider(),
        RadioListTile<WeatherUnits>(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          value: WeatherUnits.si,
          groupValue: settings.weatherUnits,
          onChanged: (value) {
            if (value != null) {
              settings.setWeatherUnits(value);
            }
          },
          title: const Text('Metric units'),
          dense: true,
        ),
        RadioListTile<WeatherUnits>(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          value: WeatherUnits.us,
          groupValue: settings.weatherUnits,
          onChanged: (value) {
            if (value != null) {
              settings.setWeatherUnits(value);
            }
          },
          title: const Text('Imperial units'),
          dense: true,
        ),
      ],
    );
  }

  Widget _dataAttribution() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: null,
          child: const Text('Weather data by Open-Meteo.com'),
        ),
      ),
    );
  }
}
