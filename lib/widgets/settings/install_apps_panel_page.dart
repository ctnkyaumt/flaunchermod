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

  /// False until the installed-app scan has answered.
  ///
  /// Nothing focusable is shown before then: the rows would all read "Install",
  /// and the OK press that opened this page is still queued behind the platform
  /// call, so it landed on whichever row had taken focus.
  bool _ready = false;

  @override
  void initState() {
    super.initState();
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
    var installed = <String>{};
    var namesFromList = <String>{};
    try {
      // One lightweight call. getApplications() ships every banner and icon
      // over the channel and the per-app applicationExists() calls added a
      // round trip each, which is what made the page sit on "Install" for a
      // second before correcting itself.
      final apps = await FLauncherChannel().getMappableApplications();
      installed = apps
          .whereType<Map>()
          .map((e) => e["packageName"])
          .whereType<String>()
          .toSet();
      namesFromList = apps
          .whereType<Map>()
          .map((e) => e["name"])
          .whereType<String>()
          .map(_normalizeAppName)
          .toSet();
    } catch (_) {
      // Leave the sets empty; every row simply offers to install.
    }

    if (!mounted) return;
    setState(() {
      _ready = true;
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
  }

  Future<void> _startInstall(AppSpec app) async {
    await context.read<AppInstallService>().startInstall(app);
    // After install (or attempt), refresh installed packages
    await _refreshInstalledPackages();
  }

  /// Every row stays pressable so the remote can move through the whole list;
  /// the rows that have nothing to do just say so.
  Future<void> _onRowPressed(AppSpec app, {required bool installed, required bool anyBusy}) async {
    if (anyBusy) {
      _say("Another install is already running");
      return;
    }
    if (installed) {
      _say("${app.name} is already installed");
      return;
    }
    if (await _confirmInstall(app)) {
      await _startInstall(app);
    }
  }

  /// Downloading and installing an APK is worth one deliberate press, and it
  /// means a stray activation lands on Cancel instead of starting a download.
  Future<bool> _confirmInstall(AppSpec app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("Install ${app.name}?"),
        content: Text("The APK will be downloaded, then Android will ask you to confirm."),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text("Install"),
          ),
        ],
      ),
    );
    return confirmed == true;
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
        if (!_ready)
          Expanded(
            child: Center(child: Text("Checking which apps are installed…")),
          )
        else
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

