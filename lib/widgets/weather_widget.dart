import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class WeatherWidget extends StatelessWidget {
  const WeatherWidget({Key? key}) : super(key: key);

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
              return _WeatherContainer(
                child: current == null
                    ? _WeatherContentPlaceholder(config: config)
                    : _WeatherContent(
                        config: config,
                        conditions: current,
                      ),
              );
            },
          );
        },
      );
}

class _WeatherContentPlaceholder extends StatelessWidget {
  final _WeatherUiConfig config;

  const _WeatherContentPlaceholder({required this.config});

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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (config.name != null && config.showCity) ...[
                    Text(config.name!),
                    const SizedBox(width: 12),
                  ],
                  const Icon(Icons.cloud, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Text('-', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            );
          },
        ),
      );

  KeyEventResult _handleKey(BuildContext context, RawKeyEvent event) {
    if (event is RawKeyUpEvent) {
      final settings = context.read<SettingsService>();
      if (settings.isSelectEvent(event)) {
        settings.setWeatherShowDetails(!settings.weatherShowDetails);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

class _WeatherContainer extends StatelessWidget {
  final Widget child;

  const _WeatherContainer({required this.child});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
                  ),
              child: child,
            ),
          ),
        ],
      );
}

class _WeatherContent extends StatefulWidget {
  final _WeatherUiConfig config;
  final WeatherConditions conditions;

  const _WeatherContent({required this.config, required this.conditions});

  @override
  State<_WeatherContent> createState() => _WeatherContentState();
}

class _WeatherContentState extends State<_WeatherContent> {
  bool _pressed = false;

  void _flashPressed() {
    if (!mounted) {
      return;
    }
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 140), () {
      if (!mounted) {
        return;
      }
      setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: true,
        onKey: (_, event) => _handleKey(context, event),
        child: Builder(
          builder: (context) {
            final hasFocus = Focus.of(context).hasFocus;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _pressed ? Colors.white12 : Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              foregroundDecoration: hasFocus
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                    )
                  : null,
              child: InkWell(
                canRequestFocus: false,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                onTap: () {
                  _flashPressed();
                  _toggleDetails(context);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _summary(context),
                    if (widget.config.showDetails) const SizedBox(width: 16),
                    if (widget.config.showDetails)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: _details(context),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  KeyEventResult _handleKey(BuildContext context, RawKeyEvent event) {
    if (event is RawKeyUpEvent) {
      final settings = context.read<SettingsService>();
      if (settings.isSelectEvent(event)) {
        _flashPressed();
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
        if (widget.config.name != null && widget.config.showCity) ...[
          Text(widget.config.name!),
          const SizedBox(width: 12),
        ],
        Icon(_iconForWeatherCode(widget.conditions.weatherCode), color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Text('${widget.conditions.temperature.round()}°',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _details(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _detailItem('${widget.conditions.apparentTemperature.round()}°', 'Feels like'),
        const SizedBox(width: 16),
        _detailItem('${widget.conditions.humidity}%', 'Humidity'),
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
