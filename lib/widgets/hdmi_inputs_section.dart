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

class HdmiInput {
  final String id;
  final String name;
  // Add other fields like icon (Uint8List?) if needed

  HdmiInput({required this.id, required this.name});

  factory HdmiInput.fromMap(Map<dynamic, dynamic> map) {
    return HdmiInput(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Unknown Input',
      // Parse icon if available: map['icon'] != null ? Uint8List.fromList(List<int>.from(map['icon'])) : null,
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
}

class HdmiInputsSection extends StatefulWidget {
  const HdmiInputsSection({Key? key}) : super(key: key);

  @override
  State<HdmiInputsSection> createState() => _HdmiInputsSectionState();
}

class _HdmiInputsSectionState extends State<HdmiInputsSection> {
  List<HdmiInput> _hdmiInputs = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _hdmiEventsSubscription;
  late FLauncherChannel _channel;

  @override
  void initState() {
    super.initState();
    // FLauncherChannel is not a provider by default, get it differently if needed
    // For now, assuming it can be instantiated directly or accessed globally/statically
    // If it's provided via Provider, use context.read<FLauncherChannel>()
    _channel = FLauncherChannel(); // Adjust if necessary
    _fetchHdmiInputs();
    _listenForHdmiEvents();
  }

  @override
  void dispose() {
    _hdmiEventsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchHdmiInputs() async {
    setState(() {
      _isLoading = true;
      // Keep previous error state if desired, or clear it:
      _error = null;
    });
    try {
      final inputs = await _channel.getHdmiInputs();
      // Ensure mounted check after async gap
      if (!mounted) return;
      setState(() {
        _hdmiInputs = inputs.map((data) => HdmiInput.fromMap(data)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed to load HDMI inputs: $e";
          _hdmiInputs = [];
          _isLoading = false;
        });
      }
    } finally {
      // Ensure loading is set to false even if mounted check fails within catch
      // Although the checks above should handle it.
      // if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  void _listenForHdmiEvents() {
    _hdmiEventsSubscription = _channel.hdmiInputStream.listen((event) {
      if (!mounted) return;
      final action = event['action'] as String?;
      setState(() {
        switch (action) {
          case 'INPUT_ADDED':
            final inputInfo = event['inputInfo'];
            if (inputInfo != null) {
              final newHdmi = HdmiInput.fromMap(inputInfo);
              // Avoid duplicates if list was re-fetched recently
              if (!_hdmiInputs.any((i) => i.id == newHdmi.id)) {
                _hdmiInputs.add(newHdmi);
              }
            }
            break;
          case 'INPUT_REMOVED':
            final inputId = event['inputId'] as String?;
            if (inputId != null) {
              _hdmiInputs.removeWhere((input) => input.id == inputId);
            }
            break;
          case 'INPUT_UPDATED':
            final inputInfo = event['inputInfo'];
            if (inputInfo != null) {
              final updatedHdmi = HdmiInput.fromMap(inputInfo);
              final index = _hdmiInputs.indexWhere((i) => i.id == updatedHdmi.id);
              if (index != -1) {
                _hdmiInputs[index] = updatedHdmi;
              }
            }
            break;
          // INPUT_STATE_CHANGED is ignored for now
        }
        // Sort inputs by numeric order (HDMI 1, HDMI 2, etc.)
        _hdmiInputs.sort((a, b) => a.numericOrder.compareTo(b.numericOrder));
      });
    }, onError: (error) {
      // Handle stream errors if necessary
      if (mounted) {
        setState(() {
          _error = "HDMI update listener error: $error";
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

    if (_hdmiInputs.isEmpty) {
      return const SizedBox(height: 126, child: Center(child: Text('No HDMI inputs detected.')));
    }

    // Sort inputs by numeric order (HDMI 1, HDMI 2, etc.)
    _hdmiInputs.sort((a, b) => a.numericOrder.compareTo(b.numericOrder));

    return SizedBox(
      height: 126,
      child: ListView.custom(
        padding: EdgeInsets.all(8),
        scrollDirection: Axis.horizontal,
        childrenDelegate: SliverChildBuilderDelegate(
          (context, index) => EnsureVisible(
            key: Key("hdmi-${_hdmiInputs[index].id}"),
            alignment: 0.1,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 200, // Fixed width to match other categories
                height: 110, // Fixed height to match other categories
                child: HdmiCard(
                  input: _hdmiInputs[index],
                  autofocus: index == 0,
                  onTap: () => _channel.launchTvInput(_hdmiInputs[index].id),
                ),
              ),
            ),
          ),
          childCount: _hdmiInputs.length,
          findChildIndexCallback: (Key key) {
            final keyValue = (key as ValueKey<String>).value;
            return _hdmiInputs.indexWhere((input) => "hdmi-${input.id}" == keyValue);
          },
        ),
      ),
    );
  }
}

class HdmiCard extends StatefulWidget {
  final HdmiInput input;
  final bool autofocus;
  final VoidCallback onTap;

  const HdmiCard({
    Key? key,
    required this.input,
    required this.autofocus,
    required this.onTap,
  }) : super(key: key);

  @override
  _HdmiCardState createState() => _HdmiCardState();
}

class _HdmiCardState extends State<HdmiCard> with SingleTickerProviderStateMixin {
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
                      Icon(Icons.settings_input_hdmi, size: 40),
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
                if (appHighlightAnimationEnabled) {
                  _animation.forward();
                  return AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) => IgnorePointer(
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          border: Focus.of(context).hasFocus
                              ? Border.all(
                                  color: _lastBorderColor =
                                      computeBorderColor(_animation.value, _lastBorderColor),
                                  width: 3)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                }
                _animation.stop();
                return SizedBox();
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
