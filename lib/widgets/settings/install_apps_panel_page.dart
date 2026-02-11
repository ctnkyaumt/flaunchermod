import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InstallAppsPanelPage extends StatefulWidget {
  static const String routeName = "install_apps_panel";

  @override
  _InstallAppsPanelPageState createState() => _InstallAppsPanelPageState();
}

class _InstallAppsPanelPageState extends State<InstallAppsPanelPage> {
  final List<AppSpec> _apps = AppInstallService.knownApps;

  final Set<String> _installedPackages = {};
  final Set<String> _installedAppNames = {};
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _focusNodes.addAll(List.generate(_apps.length, (_) => FocusNode()));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestFocus();
    });
    _refreshInstalledPackages();
  }

  @override
  void dispose() {
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _requestFocus() {
    if (!mounted) return;
    // Attempt to focus the first available (not installed) app button
    for (int i = 0; i < _apps.length; i++) {
      if (!_isInstalled(_apps[i]) && !_isInstalledByName(_apps[i])) {
        if (_focusNodes[i].canRequestFocus) {
          _focusNodes[i].requestFocus();
          return;
        }
      }
    }
    // Fallback: focus the first item if possible
    if (_focusNodes.isNotEmpty && _focusNodes[0].canRequestFocus) {
      _focusNodes[0].requestFocus();
    }
  }

  bool _isInstalled(AppSpec app) {
    final packageName = app.packageName;
    if (packageName == null) return false;
    return _installedPackages.contains(packageName);
  }

  bool _isInstalledByName(AppSpec app) => _installedAppNames.contains(app.name);

  String _normalizeAppName(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  Future<void> _refreshInstalledPackages() async {
    try {
      final channel = FLauncherChannel();
      final apps = await channel.getApplications();
      final packagesFromList = apps
          .whereType<Map>()
          .map((e) => e["packageName"])
          .whereType<String>()
          .toSet();
      final namesFromList = apps
          .whereType<Map>()
          .map((e) => e["name"])
          .whereType<String>()
          .map(_normalizeAppName)
          .toSet();

      final installed = <String>{...packagesFromList};
      for (final app in _apps) {
        final packageName = app.packageName;
        if (packageName != null && !installed.contains(packageName)) {
          final exists = await channel.applicationExists(packageName);
          if (exists) {
            installed.add(packageName);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _installedPackages
          ..clear()
          ..addAll(installed);
        _installedAppNames.clear();
        for (final app in _apps) {
          final appInstalled = _isInstalled(app) ||
              (app.packageName == null && namesFromList.contains(_normalizeAppName(app.name))) ||
              (_normalizeAppName(app.name).contains("smarttube") && namesFromList.any((n) => n.contains("smarttube"))) ||
              (_normalizeAppName(app.name).contains("blackbulb") && namesFromList.any((n) => n.contains("blackbulb")));
          if (appInstalled) {
            _installedAppNames.add(app.name);
          }
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    } catch (_) {}
  }

  Future<void> _startInstall(AppSpec app) async {
    await context.read<AppInstallService>().startInstall(app);
    // After install (or attempt), refresh installed packages
    await _refreshInstalledPackages();
  }

  @override
  Widget build(BuildContext context) {
    final installService = context.watch<AppInstallService>();
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text("Install Apps", style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
        ),
        Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: _apps.length,
            itemBuilder: (context, index) {
              final app = _apps[index];
              final name = app.name;
              final installed = _isInstalled(app) || _isInstalledByName(app);
              
              final serviceStatus = installService.status[name];
              final serviceProgress = installService.progress[name] ?? 0.0;
              final activeAppName = installService.activeAppName;
              
              final isBusy = activeAppName == name;
              final anyBusy = activeAppName != null;

              final onPressed = (installed || anyBusy) ? null : () => _startInstall(app);
              
              String statusText = serviceStatus ?? "Idle";
              if (installed) {
                statusText = "Already installed";
              }
              
              final buttonText = installed
                  ? "Installed"
                  : isBusy
                      ? "Working"
                      : "Install";

              return EnsureVisible(
                alignment: 0.5,
                child: Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(statusText),
                        if (isBusy && serviceProgress > 0)
                          LinearProgressIndicator(value: serviceProgress),
                      ],
                    ),
                    trailing: ElevatedButton(
                      focusNode: _focusNodes[index],
                      child: Text(buttonText),
                      onPressed: onPressed,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

