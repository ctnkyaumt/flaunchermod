import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/tv_keyboard_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class WeatherPanelPage extends StatefulWidget {
  static const String routeName = "weather_panel";

  @override
  State<WeatherPanelPage> createState() => _WeatherPanelPageState();
}

class _WeatherPanelPageState extends State<WeatherPanelPage> {
  String _cityDraft = '';

  bool _useCitySearch = true;
  bool _busy = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

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
        if (_useCitySearch) _citySearch(context, settings) else _coordinateInput(context, settings),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _useCitySearch = !_useCitySearch),
          child: Text(_useCitySearch ? 'Enter coordinates' : 'Search for city'),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _editButton(
            title: 'Location display name',
            value: settings.weatherLocationName ?? '',
            onPressed: () => _editLocationName(context, settings),
          ),
        ),
      ],
    );
  }

  Widget _citySearch(BuildContext context, SettingsService settings) {
    final currentName = settings.weatherLocationName ?? '';
    final display = currentName.isNotEmpty ? currentName : (_cityDraft.isNotEmpty ? _cityDraft : '');
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
              child: _editButton(
                title: 'Search for city',
                value: display,
                placeholder: 'Press OK to type',
                onPressed: () => _editCity(context),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _cityDraft.trim().isEmpty ? null : () => _applyCity(context, settings, _cityDraft),
              child: const Icon(Icons.search),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coordinateInput(BuildContext context, SettingsService settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: _editButton(
              title: 'Latitude',
              value: settings.weatherLatitude?.toString() ?? '',
              placeholder: 'Press OK to type',
              onPressed: () => _editLatitude(context, settings),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _editButton(
              title: 'Longitude',
              value: settings.weatherLongitude?.toString() ?? '',
              placeholder: 'Press OK to type',
              onPressed: () => _editLongitude(context, settings),
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

  Widget _editButton({
    required String title,
    required String value,
    required VoidCallback onPressed,
    String? placeholder,
  }) {
    final display = value.isNotEmpty ? value : (placeholder ?? '');
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        backgroundColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit, size: 18),
        ],
      ),
    );
  }

  Future<void> _editCity(BuildContext context) async {
    final next = await TvKeyboardDialog.show(
      context,
      title: 'Search for city',
      initialValue: _cityDraft,
      layout: TvKeyboardLayout.text,
    );

    if (next == null) {
      return;
    }

    setState(() {
      _cityDraft = next;
    });
  }

  Future<void> _editLocationName(BuildContext context, SettingsService settings) async {
    final next = await TvKeyboardDialog.show(
      context,
      title: 'Location display name',
      initialValue: settings.weatherLocationName ?? '',
      layout: TvKeyboardLayout.text,
    );

    if (next == null) {
      return;
    }

    await settings.setWeatherLocationName(next);
  }

  Future<void> _editLatitude(BuildContext context, SettingsService settings) async {
    final next = await TvKeyboardDialog.show(
      context,
      title: 'Latitude',
      initialValue: settings.weatherLatitude?.toString() ?? '',
      layout: TvKeyboardLayout.number,
    );

    if (next == null) {
      return;
    }

    final lat = double.tryParse(next.trim());
    await settings.setWeatherCoordinates(latitude: lat, longitude: settings.weatherLongitude);
  }

  Future<void> _editLongitude(BuildContext context, SettingsService settings) async {
    final next = await TvKeyboardDialog.show(
      context,
      title: 'Longitude',
      initialValue: settings.weatherLongitude?.toString() ?? '',
      layout: TvKeyboardLayout.number,
    );

    if (next == null) {
      return;
    }

    final lon = double.tryParse(next.trim());
    await settings.setWeatherCoordinates(latitude: settings.weatherLatitude, longitude: lon);
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
