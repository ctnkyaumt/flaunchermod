/*
 * FLauncher
 * Copyright (C) 2021-2025 Étienne Fesser & Cascade
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
        // Sort inputs maybe? e.g., by name
        _hdmiInputs.sort((a, b) => a.name.compareTo(b.name));
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
      return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return SizedBox(height: 100, child: Center(child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))));
    }

    if (_hdmiInputs.isEmpty) {
      return const SizedBox(height: 100, child: Center(child: Text('No HDMI inputs detected.')));
    }

    return Container(
      height: 100, // Adjust height as needed
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _hdmiInputs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final input = _hdmiInputs[index];
          return AspectRatio(
            aspectRatio: 16 / 9, // Or adjust aspect ratio
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  _channel.launchTvInput(input.id);
                  // Optionally show feedback
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    // TODO: Add icon if available?
                    child: Text(
                      input.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
