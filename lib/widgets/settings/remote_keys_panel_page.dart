import 'dart:async';

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class RemoteKeysPanelPage extends StatelessWidget {
  static const String routeName = "remote_keys_panel";
  static const _ignoreInitialSelectKeyCodes = {23, 66};
  static const _knownAdbKeys = <_KnownAdbKey>[
    _KnownAdbKey(label: 'Netflix', scanCode: 0x00000127),
    _KnownAdbKey(label: 'YouTube', scanCode: 0x000c00a5),
    _KnownAdbKey(label: 'Amazon Prime', scanCode: 0x000c00a1),
    _KnownAdbKey(label: 'Google Play', scanCode: 0x000c0088),
    _KnownAdbKey(label: 'Menu', scanCode: 0x00070086),
    _KnownAdbKey(label: 'Voice assistant', scanCode: 0x000c0221),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final appsService = context.watch<AppsService>();
    final bindings = settings.remoteBindings.toList()
      ..sort((a, b) {
        final k = a.keyCode.compareTo(b.keyCode);
        if (k != 0) return k;
        final s = (a.scanCode ?? 0).compareTo(b.scanCode ?? 0);
        if (s != 0) return s;
        return a.type.index.compareTo(b.type.index);
      });

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text("Remote Buttons", style: Theme.of(context).textTheme.titleLarge)),
            TextButton(
              onPressed: () async {
                final confirmed = await _confirmReset(context);
                if (confirmed != true) {
                  return;
                }
                await settings.resetRemoteControlsToDefaults();
              },
              child: const Text('RESET'),
            ),
            TextButton(
              onPressed: () async {
                await appsService.openAccessibilitySettings();
              },
              child: const Text('ACCESSIBILITY'),
            ),
            TextButton(
              onPressed: () async {
                await _addBinding(context, settings, appsService);
              },
              child: const Text('ADD'),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: bindings.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'No bindings yet. Press ADD to bind a remote button to an action.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ]
                  : bindings.map((binding) => _bindingRow(context, settings, appsService, binding)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bindingRow(BuildContext context, SettingsService settings, AppsService appsService, RemoteBinding binding) {
    final actionLabel = _bindingLabel(appsService, binding);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_bindingKeyLabel(binding), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(actionLabel, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                final updated = await _editBinding(context, appsService, binding);
                if (updated != null) {
                  await settings.upsertRemoteBinding(updated);
                }
              },
              child: const Text('CHANGE'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => settings.removeRemoteBinding(binding),
              child: const Text('REMOVE'),
            ),
          ],
        ),
      ),
    );
  }

  String _bindingKeyLabel(RemoteBinding binding) {
    final sc = binding.scanCode;
    if (sc != null && sc != 0) {
      return 'KeyCode ${binding.keyCode} (ScanCode $sc)';
    }
    return 'KeyCode ${binding.keyCode}';
  }

  String _bindingLabel(AppsService appsService, RemoteBinding binding) {
    switch (binding.type) {
      case RemoteBindingType.launchApp:
        final pkg = binding.packageName;
        if (pkg == null || pkg.isEmpty) {
          return '${binding.type.label}: (not set)';
        }
        final appName = _appNameForPackage(appsService.applications, pkg);
        return '${binding.type.label}: $appName';
      default:
        return binding.type.label;
    }
  }

  String _appNameForPackage(List<App> apps, String packageName) {
    for (final app in apps) {
      if (app.packageName == packageName) {
        return app.name;
      }
    }
    return packageName;
  }

  Future<void> _addBinding(BuildContext context, SettingsService settings, AppsService appsService) async {
    final keyEvent = await _captureAndroidKeyEvent(context, appsService, title: 'Press a remote button');
    if (keyEvent == null) {
      return;
    }

    final type = await _selectBindingType(context);
    if (type == null) {
      return;
    }

    String? packageName;
    if (type == RemoteBindingType.launchApp) {
      packageName = await _pickAppPackageName(context, appsService.applications);
      if (packageName == null) {
        return;
      }
    }

    await settings.upsertRemoteBinding(
      RemoteBinding(
        keyCode: keyEvent.keyCode,
        scanCode: keyEvent.scanCode,
        type: type,
        packageName: packageName,
      ),
    );
  }

  Future<RemoteBinding?> _editBinding(BuildContext context, AppsService appsService, RemoteBinding current) async {
    final type = await _selectBindingType(context);
    if (type == null) {
      return null;
    }

    if (type == RemoteBindingType.launchApp) {
      final packageName = await _pickAppPackageName(context, appsService.applications);
      if (packageName == null) {
        return null;
      }
      return current.copyWith(type: type, packageName: packageName);
    }

    return current.copyWith(type: type, clearPackageName: true);
  }

  Future<RemoteBindingType?> _selectBindingType(BuildContext context) async {
    return showDialog<RemoteBindingType>(
      context: context,
      builder: (context) {
        final firstFocus = FocusNode();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!firstFocus.canRequestFocus) return;
          FocusScope.of(context).requestFocus(firstFocus);
        });

        return AlertDialog(
          title: const Text('Choose action'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: FocusTraversalGroup(
              child: ListView.builder(
                itemCount: RemoteBindingType.values.length,
                itemBuilder: (context, index) {
                  final t = RemoteBindingType.values[index];
                  return ListTile(
                    focusNode: index == 0 ? firstFocus : null,
                    title: Text(t.label),
                    onTap: () => Navigator.of(context).pop(t),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _pickAppPackageName(BuildContext context, List<App> apps) async {
    final sorted = apps.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Choose app'),
          content: SizedBox(
            width: 420,
            height: 480,
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final app = sorted[index];
                return ListTile(
                  title: Text(app.name),
                  subtitle: Text(app.packageName),
                  onTap: () => Navigator.of(context).pop(app.packageName),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }

  Future<_CapturedAndroidKey?> _captureAndroidKeyEvent(
    BuildContext context,
    AppsService appsService, {
    required String title,
  }) async {
    final ignoreUntilMs = DateTime.now().millisecondsSinceEpoch + 350;
    return showDialog<_CapturedAndroidKey>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _AndroidKeyCaptureDialog(
          title: title,
          ignoreUntilMs: ignoreUntilMs,
          appsService: appsService,
          ignoreInitialKeyCodes: _ignoreInitialSelectKeyCodes,
          knownAdbKeys: _knownAdbKeys,
        );
      },
    );
  }

  Future<bool?> _confirmReset(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Revert to defaults?'),
          content: const Text('This restores the default remote button bindings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('RESET'),
            ),
          ],
        );
      },
    );
  }
}

class _CapturedAndroidKey {
  final int keyCode;
  final int scanCode;

  const _CapturedAndroidKey({required this.keyCode, required this.scanCode});
}

class _AndroidKeyCaptureDialog extends StatefulWidget {
  final String title;
  final int ignoreUntilMs;
  final AppsService appsService;
  final Set<int> ignoreInitialKeyCodes;
  final List<_KnownAdbKey> knownAdbKeys;

  const _AndroidKeyCaptureDialog({
    required this.title,
    required this.ignoreUntilMs,
    required this.appsService,
    required this.ignoreInitialKeyCodes,
    required this.knownAdbKeys,
  });

  @override
  State<_AndroidKeyCaptureDialog> createState() => _AndroidKeyCaptureDialogState();
}

class _AndroidKeyCaptureDialogState extends State<_AndroidKeyCaptureDialog> {
  StreamSubscription<dynamic>? _sub;
  bool _completed = false;
  bool _listening = false;
  int _ignoreUntilMs = 0;

  final FocusNode _captureFocus = FocusNode();
  final FocusNode _captureButtonFocus = FocusNode();

  bool _shouldIgnoreKey(int keyCode) {
    final deadlineMs = _ignoreUntilMs == 0 ? widget.ignoreUntilMs : _ignoreUntilMs;
    if (DateTime.now().millisecondsSinceEpoch >= deadlineMs) {
      return false;
    }
    return widget.ignoreInitialKeyCodes.contains(keyCode);
  }

  void _cancel() {
    if (_completed) return;
    _completed = true;
    _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    Navigator.of(context).pop(null);
  }

  void _complete(_CapturedAndroidKey key) {
    if (_completed) return;
    _completed = true;
    _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    Navigator.of(context).pop(key);
  }

  void _startListening() {
    if (_completed) return;
    if (_listening) return;
    setState(() {
      _listening = true;
      _ignoreUntilMs = DateTime.now().millisecondsSinceEpoch + 350;
    });

    _sub?.cancel();
    _sub = widget.appsService.fLauncherChannel.keyEventStream.listen((event) {
      if (!mounted || !_listening || _completed) return;
      if (event is! Map) return;
      final action = event['action'];
      if (action != 'up' && action != 'down') return;
      final keyCode = event['keyCode'];
      final scanCode = event['scanCode'];
      final repeatCount = event['repeatCount'];
      if (keyCode is! int || scanCode is! int) return;
      if (_shouldIgnoreKey(keyCode)) return;
      if (action == 'down' && repeatCount is int && repeatCount != 0) return;
      if (keyCode == 4) {
        _cancel();
        return;
      }
      _complete(_CapturedAndroidKey(keyCode: keyCode, scanCode: scanCode));
    });

    if (mounted && _captureFocus.canRequestFocus) {
      FocusScope.of(context).requestFocus(_captureFocus);
    }
  }

  void _stopListening() {
    if (!_listening) return;
    _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    setState(() {
      _listening = false;
    });
    if (_captureButtonFocus.canRequestFocus) {
      FocusScope.of(context).requestFocus(_captureButtonFocus);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_captureButtonFocus.canRequestFocus) {
        FocusScope.of(context).requestFocus(_captureButtonFocus);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _captureFocus.dispose();
    _captureButtonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: FocusTraversalGroup(
          child: FocusScope(
            autofocus: true,
            child: Focus(
              focusNode: _captureFocus,
              canRequestFocus: _listening,
              onKey: (_, event) {
                if (!_listening) return KeyEventResult.ignored;
                if (event is! RawKeyUpEvent) {
                  return KeyEventResult.handled;
                }
                final data = event.data;
                if (data is RawKeyEventDataAndroid && _shouldIgnoreKey(data.keyCode)) {
                  return KeyEventResult.handled;
                }
                if (data is RawKeyEventDataAndroid) {
                  if (data.keyCode == 4) {
                    _cancel();
                    return KeyEventResult.handled;
                  }
                  _complete(_CapturedAndroidKey(keyCode: data.keyCode, scanCode: data.scanCode));
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Text(
                _listening
                    ? 'Listening… press the remote button now.'
                    : 'Select CAPTURE, then press the remote button you want to bind.\n\nIf the TV steals the key (Netflix/YouTube/etc.), use PICK instead.',
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            _stopListening();
            final picked = await showDialog<_CapturedAndroidKey>(
              context: context,
              builder: (context) {
                Future<_CapturedAndroidKey?> pickCustom() async {
                  final controller = TextEditingController();
                  final result = await showDialog<int>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Custom scanCode (hex)'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: 'e.g. 00f0 or 0x00f0'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(null),
                            child: const Text('CANCEL'),
                          ),
                          TextButton(
                            onPressed: () {
                              final raw = controller.text.trim().toLowerCase();
                              final normalized = raw.startsWith('0x') ? raw.substring(2) : raw;
                              final parsed = int.tryParse(normalized, radix: 16);
                              Navigator.of(context).pop(parsed);
                            },
                            child: const Text('OK'),
                          ),
                        ],
                      );
                    },
                  );
                  if (result == null) return null;
                  return _CapturedAndroidKey(keyCode: 0, scanCode: result);
                }

                return SimpleDialog(
                  title: const Text('Pick a special key'),
                  children: widget.knownAdbKeys
                      .map(
                        (k) => SimpleDialogOption(
                          onPressed: () => Navigator.of(context).pop(_CapturedAndroidKey(keyCode: 0, scanCode: k.scanCode)),
                          child: Text('${k.label} (scanCode 0x${k.scanCode.toRadixString(16)})'),
                        ),
                      )
                      .followedBy([
                        SimpleDialogOption(
                          onPressed: () async {
                            final custom = await pickCustom();
                            if (context.mounted) {
                              Navigator.of(context).pop(custom);
                            }
                          },
                          child: const Text('Custom…'),
                        ),
                      ]).toList(),
                );
              },
            );
            if (picked == null) {
              return;
            }
            _complete(picked);
          },
          child: const Text('PICK'),
        ),
        TextButton(
          focusNode: _captureButtonFocus,
          onPressed: () {
            if (_listening) {
              _stopListening();
              return;
            }
            _startListening();
          },
          child: Text(_listening ? 'STOP' : 'CAPTURE'),
        ),
        TextButton(
          onPressed: _cancel,
          child: const Text('CANCEL'),
        ),
      ],
    );
  }
}

class _KnownAdbKey {
  final String label;
  final int scanCode;

  const _KnownAdbKey({required this.label, required this.scanCode});
}
