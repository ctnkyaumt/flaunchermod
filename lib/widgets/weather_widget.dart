import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class WeatherWidget extends StatelessWidget {
  const WeatherWidget({super.key});

  @override
  Widget build(BuildContext context) => Selector<SettingsService, _WeatherUiConfig>(
        selector: (_, settings) => _WeatherUiConfig(
          enabled: settings.weatherEnabled,
          name: settings.weatherLocationName,
          showCity: settings.weatherShowCity,
          showDetails: settings.weatherShowDetails,
        ),
        builder: (context, config, _) {
          if (!config.enabled) {
            return const SizedBox.shrink();
          }

          return Consumer<WeatherService>(
            builder: (context, weatherService, _) {
              final current = weatherService.findCurrent(DateTime.now());
              if (current == null) {
                return const _WeatherContainer(child: Text('-'));
              }

              return _WeatherContainer(
                child: _WeatherContent(
                  config: config,
                  conditions: current,
                ),
              );
            },
          );
        },
      );
}

class _WeatherContainer extends StatelessWidget {
  final Widget child;

  const _WeatherContainer({required this.child});

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.titleMedium!.copyWith(
                shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
              ),
          child: child,
        ),
      );
}

class _WeatherContent extends StatelessWidget {
  final _WeatherUiConfig config;
  final WeatherConditions conditions;

  const _WeatherContent({required this.config, required this.conditions});

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: true,
        onKey: (_, event) => _handleKey(context, event),
        child: Builder(
          builder: (context) {
            final hasFocus = Focus.of(context).hasFocus;
            final border = hasFocus ? Border.all(color: Colors.white, width: 2) : null;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: border,
              ),
              child: InkWell(
                onTap: () => _toggleDetails(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _summary(context),
                    if (config.showDetails) const SizedBox(height: 8),
                    if (config.showDetails) _details(context),
                  ],
                ),
              ),
            );
          },
        ),
      );

  KeyEventResult _handleKey(BuildContext context, RawKeyEvent event) {
    if (event is RawKeyUpEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA) {
        _toggleDetails(context);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _toggleDetails(BuildContext context) {
    final settings = context.read<SettingsService>();
    settings.setWeatherShowDetails(!settings.weatherShowDetails);
  }

  Widget _summary(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (config.name != null && config.showCity) ...[
          Text(config.name!),
          const SizedBox(width: 12),
        ],
        Icon(_iconForWeatherCode(conditions.weatherCode), color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Text('${conditions.temperature.round()}°', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _details(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _detailItem('${conditions.apparentTemperature.round()}°', 'Feels like'),
        const SizedBox(width: 16),
        _detailItem('${conditions.humidity}%', 'Humidity'),
      ],
    );
  }

  Widget _detailItem(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  IconData _iconForWeatherCode(int weatherCode) {
    if (weatherCode == 0 || weatherCode == 1) {
      return Icons.wb_sunny;
    }

    if (weatherCode == 2 || weatherCode == 3) {
      return Icons.cloud;
    }

    if (weatherCode == 95 || weatherCode == 96 || weatherCode == 99) {
      return Icons.thunderstorm;
    }

    if (weatherCode >= 71 && weatherCode <= 86) {
      return Icons.ac_unit;
    }

    if (weatherCode >= 51 && weatherCode <= 67) {
      return Icons.umbrella;
    }

    if (weatherCode >= 80 && weatherCode <= 82) {
      return Icons.umbrella;
    }

    return Icons.cloud;
  }
}

class _WeatherUiConfig {
  final bool enabled;
  final String? name;
  final bool showCity;
  final bool showDetails;

  const _WeatherUiConfig({
    required this.enabled,
    required this.name,
    required this.showCity,
    required this.showDetails,
  });
}
