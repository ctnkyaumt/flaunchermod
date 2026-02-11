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
                  Text('KeyCode ${binding.keyCode}', style: Theme.of(context).textTheme.bodyMedium),
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
              onPressed: () => settings.removeRemoteBinding(binding.keyCode),
              child: const Text('REMOVE'),
            ),
          ],
        ),
      ),
    );
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
    final keyCode = await _captureAndroidKeyCode(context, title: 'Press a remote button');
    if (keyCode == null) {
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

    await settings.upsertRemoteBinding(RemoteBinding(keyCode: keyCode, type: type, packageName: packageName));
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

  Future<int?> _captureAndroidKeyCode(BuildContext context, {required String title}) async {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
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
                  final data = event.data;
                  if (data is RawKeyEventDataAndroid) {
                    Navigator.of(context).pop(data.keyCode);
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
