import 'dart:async';
import 'dart:io';

import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class BackupRestorePanelPage extends StatefulWidget {
  static const String routeName = "backup_restore_panel";

  @override
  _BackupRestorePanelPageState createState() => _BackupRestorePanelPageState();
}

class _BackupRestorePanelPageState extends State<BackupRestorePanelPage> {
  static const _browse = Object();
  bool _busy = false;
  bool _loading = false;
  String? _status;

  FLauncherChannel get _channel => context.read<AppsService>().fLauncherChannel;

  BackupService _service() => BackupService(
    context.read<FLauncherDatabase>(),
    context.read<SettingsService>(),
    buttonMappings: context.read<ButtonMappingService>(),
    wallpaper: context.read<WallpaperService>(),
    channel: _channel,
  );

  void _start(String status) {
    setState(() {
      _busy = true;
      _loading = true;
      _status = status;
    });
  }

  void _finish() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _loading = false;
      _status = null;
    });
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $error")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text("Backup & Restore"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(_status ?? "Processing..."),
              ],
            ))
          : ListView(
              children: [
                ListTile(
                  leading: Icon(Icons.save),
                  title: Text("Create Backup"),
                  subtitle: Text("Save settings, layout, and app list to file"),
                  enabled: !_busy,
                  onTap: _busy ? null : _createBackup,
                ),
                ListTile(
                  leading: Icon(Icons.restore),
                  title: Text("Restore from Backup"),
                  subtitle: Text("Restore from a previously saved file"),
                  enabled: !_busy,
                  onTap: _busy ? null : _pickBackupFile,
                ),
              ],
            ),
    );
  }

  Future<void> _createBackup() async {
    if (_busy || !mounted) return;
    _start("Creating backup...");
    try {
      final location = await _service().saveBackup();
      if (!mounted) return;
      setState(() { _loading = false; });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Backup Created"),
          content: Text("Backup saved to:\n$location"),
          actions: [
            TextButton(
              autofocus: true,
              child: Text("OK"),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      _finish();
    }
  }

  Future<List<_BackupEntry>> _listBackups() async {
    final entries = <String, _BackupEntry>{};
    void add(_BackupEntry entry) {
      if (!entry.name.startsWith("flauncher_backup_") || !entry.name.endsWith(".json")) return;
      final existing = entries[entry.name];
      if (existing == null || entry.modified.isAfter(existing.modified)) entries[entry.name] = entry;
    }

    if (Platform.isAndroid) {
      try {
        final items = await _channel.listBackupJsonInDownloads();
        if (!mounted) return [];
        for (final item in items) {
          if (item is! Map) continue;
          final name = item["name"];
          final uri = item["uri"];
          if (name is! String || uri is! String || uri.isEmpty) continue;
          final modified = item["modified"];
          final milliseconds = modified is int ? modified : int.tryParse(modified?.toString() ?? "") ?? 0;
          add(_BackupEntry(name: name, modified: DateTime.fromMillisecondsSinceEpoch(milliseconds), uri: uri));
        }
      } catch (error) {
        debugPrint("Error listing Downloads backups: $error");
      }
    }

    final locations = <Directory?>[];
    try {
      locations.add(await getApplicationDocumentsDirectory());
    } catch (error) {
      debugPrint("Error finding private backups: $error");
    }
    if (!mounted) return [];
    if (Platform.isAndroid) {
      locations.addAll([
        Directory("/storage/emulated/0/Download"),
        Directory("/storage/emulated/0/Downloads"),
        Directory("/storage/self/primary/Download"),
        Directory("/storage/self/primary/Downloads"),
        Directory("/sdcard/Download"),
        Directory("/sdcard/Downloads"),
      ]);
      try {
        locations.add(await getExternalStorageDirectory());
      } catch (error) {
        debugPrint("Error finding external backups: $error");
      }
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        locations.add(await getDownloadsDirectory());
      } catch (error) {
        debugPrint("Error finding Downloads directory: $error");
      }
    }
    if (!mounted) return [];
    final scanned = <String>{};
    for (final directory in locations) {
      if (directory == null || !scanned.add(directory.path)) continue;
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (!mounted) return [];
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (!name.startsWith("flauncher_backup_") || !name.endsWith(".json")) continue;
          try {
            final stat = await entity.stat();
            if (!mounted) return [];
            add(_BackupEntry(name: name, modified: stat.modified, file: entity));
          } catch (error) {
            debugPrint("Error reading backup metadata: $error");
          }
        }
      } catch (error) {
        debugPrint("Error listing files in ${directory.path}: $error");
      }
    }
    return entries.values.toList()..sort((a, b) => b.modified.compareTo(a.modified));
  }

  Future<void> _pickBackupFile() async {
    if (_busy || !mounted) return;
    _start("Finding backups...");
    try {
      final entries = await _listBackups();
      if (!mounted) return;
      setState(() { _loading = false; });
      final picked = await showDialog<Object>(
        context: context,
        builder: (ctx) => FocusTraversalGroup(
          child: AlertDialog(
            title: Text("Select Backup"),
            content: SizedBox(
              width: double.maxFinite,
              child: entries.isEmpty
                  ? Text("No backups found")
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          title: Text(entry.name),
                          subtitle: Text(entry.modified.toString()),
                          onTap: () => Navigator.pop(ctx, entry),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(ctx),
                child: Text("Cancel"),
              ),
              if (Platform.isAndroid) TextButton.icon(
                icon: Icon(Icons.folder_open),
                label: Text("Browse"),
                onPressed: () => Navigator.pop(ctx, _browse),
              ),
            ],
          ),
        ),
      );
      if (!mounted || picked == null) return;
      if (identical(picked, _browse)) {
        final content = await _channel.pickBackupJson();
        if (!mounted || content == null) return;
        await _restoreBackup(content: content);
      } else if (picked is _BackupEntry) {
        if (picked.file != null) {
          await _restoreBackup(file: picked.file);
        } else if (picked.uri != null) {
          final content = await _channel.readContentUri(picked.uri!);
          if (!mounted) return;
          if (content == null) throw FormatException("Unable to read backup");
          await _restoreBackup(content: content);
        }
      }
    } catch (error) {
      _showError(error);
    } finally {
      _finish();
    }
  }

  Future<void> _restoreBackup({File? file, String? content}) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => FocusTraversalGroup(
        child: AlertDialog(
          title: Text("Restore Backup?"),
          content: Text("This will replace your current layout and saved settings, including button mappings and wallpaper when present."),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text("Restore"),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _loading = true;
      _status = "Restoring backup...";
    });
    final service = _service();
    final missingApps = file != null
        ? await service.restoreBackup(file)
        : await service.restoreBackupFromContent(content!);
    if (!mounted) return;
    await context.read<AppsService>().reloadAfterRestore();
    if (!mounted) return;
    setState(() { _loading = false; });
    if (missingApps.isNotEmpty) {
      await _installMissingApps(missingApps);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Restore completed successfully")));
    }
  }

  Future<void> _installMissingApps(List<AppSpec> apps) async {
    final installService = context.read<AppInstallService>();
    final appsService = context.read<AppsService>();
    for (var i = 0; i < apps.length; i++) {
      if (!mounted) return;
      final app = apps[i];
      final shouldInstall = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text("Restore App (${i + 1}/${apps.length})"),
          content: Text("Do you want to install ${app.name}?"),
          actions: [
            TextButton(
              autofocus: true,
              child: Text("Skip"),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            TextButton(
              child: Text("Install"),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (shouldInstall == true) {
        await installService.checkAndRequestPermission();
        if (!mounted) return;
        unawaited(installService.startInstall(app));
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _InstallProgressDialog(
            app: app,
            packageStream: appsService.packageAddedStream,
          ),
        );
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("App restoration completed")));
  }
}

class _BackupEntry {
  final String name;
  final DateTime modified;
  final File? file;
  final String? uri;

  _BackupEntry({required this.name, required this.modified, this.file, this.uri});
}

class _InstallProgressDialog extends StatefulWidget {
  final AppSpec app;
  final Stream<String> packageStream;

  const _InstallProgressDialog({required this.app, required this.packageStream});

  @override
  _InstallProgressDialogState createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<_InstallProgressDialog> {
  StreamSubscription? _subscription;
  Timer? _closeTimer;
  bool _installed = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.packageStream.listen((packageName) {
      if (!mounted || _installed || packageName != widget.app.packageName) return;
      setState(() { _installed = true; });
      _closeTimer = Timer(Duration(milliseconds: 1500), () {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _closeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppInstallService>(
      builder: (context, service, _) {
        final status = _installed ? "Installed!" : (service.status[widget.app.name] ?? "Starting...");
        return AlertDialog(
          title: Text("Installing ${widget.app.name}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_installed) CircularProgressIndicator() else Icon(Icons.check_circle, color: Colors.green, size: 48),
              SizedBox(height: 16),
              Text(status),
            ],
          ),
          actions: [
            TextButton(
              autofocus: true,
              child: Text(_installed ? "Next" : "Done"),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }
}
