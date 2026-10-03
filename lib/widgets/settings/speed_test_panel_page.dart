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
 */

import 'dart:math' as math;

import 'package:flauncher/providers/speed_test_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpeedTestPanelPage extends StatefulWidget {
  static const routeName = 'speed_test_panel';
  final SpeedTestService? service;

  const SpeedTestPanelPage({Key? key, this.service}) : super(key: key);

  @override
  State<SpeedTestPanelPage> createState() => _SpeedTestPanelPageState();
}

class _SpeedTestPanelPageState extends State<SpeedTestPanelPage> with WidgetsBindingObserver {
  late final SpeedTestService _service = widget.service ?? SpeedTestService();
  final _actionFocus = FocusNode();
  bool _backPressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _backPressed = false;
      _service.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.cancel();
    if (widget.service == null) _service.dispose();
    _actionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
        onWillPop: () async {
          _service.cancel();
          return true;
        },
        child: Focus(
          canRequestFocus: false,
          onKey: (_, event) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.goBack ||
                (event.data is RawKeyEventDataAndroid &&
                    (event.data as RawKeyEventDataAndroid).keyCode == 4)) {
              if (event is RawKeyDownEvent) {
                // Keep focus here until release so repeats and Android's
                // Back-up cannot reach the settings route behind this page.
                _backPressed = true;
              } else if (event is RawKeyUpEvent) {
                final wasPressed = _backPressed;
                _backPressed = false;
                if (wasPressed && ModalRoute.of(context)?.isCurrent == true) {
                  _service.cancel();
                  Navigator.of(context).maybePop();
                }
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: AnimatedBuilder(
            animation: _service,
            builder: (context, _) => SingleChildScrollView(
              child: Column(
                children: [
                  Text('Speed Test', style: Theme.of(context).textTheme.titleLarge),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SpeedDial(
                          label: 'DOWNLOAD',
                          color: Colors.cyanAccent,
                          value: _service.phase == SpeedTestPhase.download
                              ? _service.liveMbps
                              : _service.downloadMbps,
                          active: _service.phase == SpeedTestPhase.download,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SpeedDial(
                          label: 'UPLOAD',
                          color: Colors.deepPurpleAccent.shade100,
                          value: _service.phase == SpeedTestPhase.upload ? _service.liveMbps : _service.uploadMbps,
                          active: _service.phase == SpeedTestPhase.upload,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('HTTPS latency  ${_service.latencyMs?.toStringAsFixed(0) ?? '—'} ms'),
                  const SizedBox(height: 16),
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _service.isRunning
                        ? (_service.phase == SpeedTestPhase.latency ? null : _service.progress)
                        : (_service.phase == SpeedTestPhase.complete ? 1 : 0),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    autofocus: true,
                    focusNode: _actionFocus,
                    style: ButtonStyle(
                      minimumSize: MaterialStateProperty.all(const Size(double.infinity, 48)),
                      side: MaterialStateProperty.resolveWith((states) => BorderSide(
                            color: states.contains(MaterialState.focused) ? Colors.white : Colors.white24,
                            width: 2,
                          )),
                    ),
                    onPressed: () {
                      if (_service.isRunning) {
                        _service.cancel();
                      } else {
                        _service.start();
                      }
                    },
                    icon: Icon(_service.isRunning ? Icons.stop : Icons.speed),
                    label: Text(_service.isRunning ? 'Cancel test' : 'Start test'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tests your TV’s connection to Cloudflare.\n'
                    'About 25 seconds, up to 192 MiB of test data.\n'
                    'Cloudflare receives your IP address.\n'
                    'Results are HTTPS estimates and vary by server.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_service.sampleLimited)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Data limit reached; measured a shorter sample.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  String get _status {
    switch (_service.phase) {
      case SpeedTestPhase.ready:
        return 'Ready when you are';
      case SpeedTestPhase.latency:
        return 'Measuring latency…';
      case SpeedTestPhase.download:
        return 'Measuring download…';
      case SpeedTestPhase.upload:
        return 'Measuring upload…';
      case SpeedTestPhase.complete:
        return 'Test complete';
      case SpeedTestPhase.cancelled:
        return 'Test cancelled';
      case SpeedTestPhase.failed:
        return _service.error ?? 'Test failed. Please retry.';
    }
  }
}

class _SpeedDial extends StatelessWidget {
  final String label;
  final Color color;
  final double? value;
  final bool active;

  const _SpeedDial({required this.label, required this.color, required this.value, required this.active});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label ${value?.toStringAsFixed(1) ?? 'not measured'} megabits per second',
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              width: 140,
              child: CustomPaint(
                painter: _DialPainter(value ?? 0, color, active),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(value?.toStringAsFixed(1) ?? '—',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color)),
                    const Text('Mbps'),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _DialPainter extends CustomPainter {
  final double value;
  final Color color;
  final bool active;

  _DialPainter(this.value, this.color, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2 - 8, size.height - 20);
    final center = Offset(size.width / 2, radius + 10);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = Colors.white12;
    canvas.drawArc(rect, math.pi, math.pi, false, paint);
    // Log scale keeps the gauge useful on both slow Wi-Fi and gigabit connections.
    final fraction = (math.log(1 + math.max(0, value)) / math.log(1001)).clamp(0.0, 1.0).toDouble();
    paint.color = color.withOpacity(active || value > 0 ? 1 : 0.3);
    canvas.drawArc(rect, math.pi, math.pi * fraction, false, paint);
    final angle = math.pi + math.pi * fraction;
    paint.strokeWidth = 2;
    canvas.drawLine(center, center + Offset(math.cos(angle), math.sin(angle)) * (radius - 12), paint);
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color || oldDelegate.active != active;
}
