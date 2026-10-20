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

/*
 * FLauncher
 * Copyright (C) 2021-2025 Étienne Fesser 
 *
 * 2025 ctnkyaumt & Cascade
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../flauncher_channel.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/color_helpers.dart';
import 'package:flauncher/widgets/ensure_visible.dart';

class TvInput {
  static const typeTuner = 0;
  static const typeComposite = 1001;
  static const typeSvideo = 1002;
  static const typeScart = 1003;
  static const typeComponent = 1004;
  static const typeVga = 1005;
  static const typeDvi = 1006;
  static const typeHdmi = 1007;
  static const typeDisplayPort = 1008;

  // Same order the native catalog uses for the Other row.
  static const _otherOrder = [
    typeTuner, typeComposite, typeSvideo, typeScart, typeComponent, typeVga, typeDvi, typeDisplayPort,
  ];

  final String id;
  final String name;
  final int? type;
  final bool isHdmi;

  TvInput({required this.id, required this.name, this.type, required this.isHdmi});

  factory TvInput.fromMap(Map<dynamic, dynamic> map) {
    return TvInput(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Unknown Input',
      type: map['type'] as int?,
      isHdmi: (map['group'] as String? ?? 'hdmi') == 'hdmi',
    );
  }

  // Extract numeric value for sorting
  int get numericOrder {
    final RegExp regExp = RegExp(r'(\d+)');
    final match = regExp.firstMatch(name);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }

  int get _otherRank {
    final index = _otherOrder.indexOf(type ?? -1);
    return index >= 0 ? index : _otherOrder.length;
  }

  IconData get icon {
    if (isHdmi) return Icons.settings_input_hdmi;
    switch (type) {
      case typeTuner:
        return Icons.live_tv;
      case typeComposite:
      case typeScart:
        return Icons.settings_input_composite;
      case typeComponent:
        return Icons.settings_input_component;
      case typeSvideo:
        return Icons.settings_input_svideo;
      case typeVga:
      case typeDvi:
      case typeDisplayPort:
        return Icons.desktop_windows;
      default:
        return Icons.input;
    }
  }

  static int compareHdmi(TvInput a, TvInput b) => a.numericOrder.compareTo(b.numericOrder);

  static int compareOther(TvInput a, TvInput b) {
    final byRank = a._otherRank.compareTo(b._otherRank);
    return byRank != 0 ? byRank : a.id.compareTo(b.id);
  }
}

class TvInputsSection extends StatefulWidget {
  const TvInputsSection({Key? key}) : super(key: key);

  @override
  State<TvInputsSection> createState() => _TvInputsSectionState();
}

class _TvInputsSectionState extends State<TvInputsSection> {
  List<TvInput> _hdmiInputs = [];
  List<TvInput> _otherInputs = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _inputEventsSubscription;
  late FLauncherChannel _channel;

  @override
  void initState() {
    super.initState();
    // FLauncherChannel is not a provider by default, get it differently if needed
    // For now, assuming it can be instantiated directly or accessed globally/statically
    // If it's provided via Provider, use context.read<FLauncherChannel>()
    _channel = FLauncherChannel(); // Adjust if necessary
    _fetchInputs();
    _listenForInputEvents();
  }

  @override
  void dispose() {
    _inputEventsSubscription?.cancel();
    super.dispose();
  }

  void _sortInputs() {
    _hdmiInputs.sort(TvInput.compareHdmi);
    _otherInputs.sort(TvInput.compareOther);
  }

  void _upsert(TvInput input) {
    _hdmiInputs.removeWhere((i) => i.id == input.id);
    _otherInputs.removeWhere((i) => i.id == input.id);
    (input.isHdmi ? _hdmiInputs : _otherInputs).add(input);
  }

  Future<void> _fetchInputs() async {
    setState(() {
      _isLoading = true;
      // Keep previous error state if desired, or clear it:
      _error = null;
    });
    try {
      final inputs = await _channel.getTvInputs();
      // Ensure mounted check after async gap
      if (!mounted) return;
      setState(() {
        final parsed = inputs.map((data) => TvInput.fromMap(data)).toList();
        _hdmiInputs = parsed.where((i) => i.isHdmi).toList();
        _otherInputs = parsed.where((i) => !i.isHdmi).toList();
        _sortInputs();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed to load inputs: $e";
          _hdmiInputs = [];
          _otherInputs = [];
          _isLoading = false;
        });
      }
    }
  }

  void _listenForInputEvents() {
    _inputEventsSubscription = _channel.hdmiInputStream.listen((event) {
      if (!mounted) return;
      final action = event['action'] as String?;
      setState(() {
        switch (action) {
          case 'INPUT_ADDED':
            final inputInfo = event['inputInfo'];
            if (inputInfo != null) {
              _upsert(TvInput.fromMap(inputInfo));
            }
            break;
          case 'INPUT_REMOVED':
            final inputId = event['inputId'] as String?;
            if (inputId != null) {
              _hdmiInputs.removeWhere((input) => input.id == inputId);
              _otherInputs.removeWhere((input) => input.id == inputId);
            }
            break;
          case 'INPUT_UPDATED':
            final inputInfo = event['inputInfo'];
            if (inputInfo != null) {
              final updated = TvInput.fromMap(inputInfo);
              final known = _hdmiInputs.any((i) => i.id == updated.id) || _otherInputs.any((i) => i.id == updated.id);
              if (known) {
                _upsert(updated);
              }
            }
            break;
          // INPUT_STATE_CHANGED is ignored for now
        }
        _sortInputs();
      });
    }, onError: (error) {
      // Handle stream errors if necessary
      if (mounted) {
        setState(() {
          _error = "Input update listener error: $error";
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Show placeholder or loading indicator for the section height
      return const SizedBox(height: 126, child: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return SizedBox(height: 126, child: Center(child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subtitle(context, "HDMI"),
        if (_hdmiInputs.isEmpty)
          const SizedBox(height: 126, child: Center(child: Text('No HDMI inputs detected.')))
        else
          _row(_hdmiInputs, autofocusFirst: true),
        if (_otherInputs.isNotEmpty) ...[
          _subtitle(context, "Other"),
          _row(_otherInputs, autofocusFirst: _hdmiInputs.isEmpty),
        ],
      ],
    );
  }

  Widget _subtitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _row(List<TvInput> inputs, {required bool autofocusFirst}) {
    return SizedBox(
      height: 126,
      child: ListView.custom(
        padding: EdgeInsets.all(8),
        scrollDirection: Axis.horizontal,
        childrenDelegate: SliverChildBuilderDelegate(
          (context, index) => EnsureVisible(
            key: Key("input-${inputs[index].id}"),
            alignment: 0.1,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 200, // Fixed width to match other categories
                height: 110, // Fixed height to match other categories
                child: TvInputCard(
                  input: inputs[index],
                  autofocus: autofocusFirst && index == 0,
                  onTap: () => _channel.launchTvInput(inputs[index].id),
                ),
              ),
            ),
          ),
          childCount: inputs.length,
          findChildIndexCallback: (Key key) {
            final keyValue = (key as ValueKey<String>).value;
            final index = inputs.indexWhere((input) => "input-${input.id}" == keyValue);
            return index < 0 ? null : index;
          },
        ),
      ),
    );
  }
}

class TvInputCard extends StatefulWidget {
  final TvInput input;
  final bool autofocus;
  final VoidCallback onTap;

  const TvInputCard({
    Key? key,
    required this.input,
    required this.autofocus,
    required this.onTap,
  }) : super(key: key);

  @override
  _TvInputCardState createState() => _TvInputCardState();
}

class _TvInputCardState extends State<TvInputCard> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 800),
  );
  Color _lastBorderColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _animation.addStatusListener((animationStatus) {
      switch (animationStatus) {
        case AnimationStatus.completed:
          _animation.reverse();
          break;
        case AnimationStatus.dismissed:
          _animation.forward();
          break;
        case AnimationStatus.forward:
        case AnimationStatus.reverse:
          // nothing to do
          break;
      }
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      transformAlignment: Alignment.center,
      transform: _scaleTransform(context),
      child: Material(
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        elevation: Focus.of(context).hasFocus ? 16 : 0,
        shadowColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              autofocus: widget.autofocus,
              focusColor: Colors.transparent,
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.input.icon, size: 40),
                      SizedBox(height: 8),
                      Text(
                        widget.input.name,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                duration: Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                opacity: Focus.of(context).hasFocus ? 0 : 0.10,
                child: Container(color: Colors.black),
              ),
            ),
            Selector<SettingsService, bool>(
              selector: (_, settingsService) => settingsService.appHighlightAnimationEnabled,
              builder: (context, appHighlightAnimationEnabled, __) {
                // Only the focused card shows the border, so only it needs a ticker.
                if (!appHighlightAnimationEnabled || !Focus.of(context).hasFocus) {
                  if (_animation.isAnimating) {
                    _animation.stop();
                  }
                  return const SizedBox.shrink();
                }
                _animation.forward();
                return AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) => IgnorePointer(
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _lastBorderColor = computeBorderColor(_animation.value, _lastBorderColor),
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Matrix4 _scaleTransform(BuildContext context) {
    final scale = Focus.of(context).hasFocus ? 1.1 : 1.0;
    return Matrix4.diagonal3Values(scale, scale, 1.0);
  }
}
