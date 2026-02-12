import 'dart:async';

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class RemoteKeysPanelPage extends StatelessWidget {
  static const String routeName = "remote_keys_panel";

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
        return SimpleDialog(
          title: const Text('Choose action'),
          children: RemoteBindingType.values
              .map(
                (t) => SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(t),
                  child: Text(t.label),
                ),
              )
              .toList(),
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

  const _AndroidKeyCaptureDialog({
    required this.title,
    required this.ignoreUntilMs,
    required this.appsService,
  });

  @override
  State<_AndroidKeyCaptureDialog> createState() => _AndroidKeyCaptureDialogState();
}

class _AndroidKeyCaptureDialogState extends State<_AndroidKeyCaptureDialog> {
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.appsService.fLauncherChannel.keyEventStream.listen((event) {
      if (!mounted) return;
      if (DateTime.now().millisecondsSinceEpoch < widget.ignoreUntilMs) return;
      if (event is! Map) return;
      final action = event['action'];
      if (action != 'up') return;
      final keyCode = event['keyCode'];
      final scanCode = event['scanCode'];
      if (keyCode is! int || scanCode is! int) return;
      Navigator.of(context).pop(_CapturedAndroidKey(keyCode: keyCode, scanCode: scanCode));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: FocusTraversalGroup(
        child: FocusScope(
          autofocus: true,
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            onKey: (_, event) {
              if (event is! RawKeyUpEvent) {
                return KeyEventResult.handled;
              }
              if (DateTime.now().millisecondsSinceEpoch < widget.ignoreUntilMs) {
                return KeyEventResult.handled;
              }
              final data = event.data;
              if (data is RawKeyEventDataAndroid) {
                Navigator.of(context).pop(_CapturedAndroidKey(keyCode: data.keyCode, scanCode: data.scanCode));
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: const Text('Press a button on your TV remote to assign it.'),
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
  }
}
