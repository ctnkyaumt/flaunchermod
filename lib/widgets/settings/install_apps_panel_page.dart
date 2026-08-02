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

  /// When the page was opened.
  ///
  /// The OK press that opens this page keeps being delivered after the first
  /// row has taken focus, which started an install nobody asked for. Ignore
  /// activations for a moment so that press cannot land on a button.
  late final DateTime _openedAt;
  static const _openGrace = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _refreshInstalledPackages();
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
    } catch (_) {}
  }

  Future<void> _startInstall(AppSpec app) async {
    await context.read<AppInstallService>().startInstall(app);
    // After install (or attempt), refresh installed packages
    await _refreshInstalledPackages();
  }

  /// Every row stays pressable so the remote can move through the whole list;
  /// the rows that have nothing to do just say so.
  void _onRowPressed(AppSpec app, {required bool installed, required bool anyBusy}) {
    if (DateTime.now().difference(_openedAt) < _openGrace) {
      return;
    }
    if (anyBusy) {
      _say("Another install is already running");
      return;
    }
    if (installed) {
      _say("${app.name} is already installed");
      return;
    }
    _startInstall(app);
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

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
                      autofocus: index == 0,
                      child: Text(buttonText),
                      // Never null: a disabled button cannot take focus, which
                      // made the list stop dead at the first installed app.
                      onPressed: () =>
                          _onRowPressed(app, installed: installed, anyBusy: anyBusy),
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

