import 'dart:async';
import 'dart:io';

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class BackupRestorePanelPage extends StatefulWidget {
  static const String routeName = "backup_restore_panel";

  @override
  _BackupRestorePanelPageState createState() => _BackupRestorePanelPageState();
}

class _BackupRestorePanelPageState extends State<BackupRestorePanelPage> {
  bool _loading = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    // Request storage permission immediately when opening the panel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });
  }

  Future<void> _requestPermissions() async {
    try {
      final channel = Provider.of<AppsService>(context, listen: false).fLauncherChannel;
      await channel.requestStoragePermission();
    } catch (e) {
      debugPrint("Failed to request storage permission: $e");
    }
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
                  onTap: _createBackup,
                ),
                ListTile(
                  leading: Icon(Icons.restore),
                  title: Text("Restore from Backup"),
                  subtitle: Text("Restore from a previously saved file"),
                  onTap: _pickBackupFile,
                ),
              ],
            ),
    );
  }

  Future<void> _createBackup() async {
    setState(() {
      _loading = true;
      _status = "Creating backup...";
    });

    try {
      final db = Provider.of<FLauncherDatabase>(context, listen: false);
      final settings = Provider.of<SettingsService>(context, listen: false);
      final service = BackupService(db, settings);
      final file = await service.createBackup();

      setState(() {
        _loading = false;
      });

      // Ask to upload
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Backup Created"),
          content: Text("Backup saved to:\n${file.path}\n\nDo you want to backup to cloud (GDrive)?"),
          actions: [
            TextButton(
              child: Text("No (Local Only)"),
              onPressed: () => Navigator.pop(ctx, false),
            ),
            TextButton(
              child: Text("Yes (Cloud)"),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );

      if (result == true) {
        await service.shareBackup(file);
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _pickBackupFile() async {
    await _requestPermissions();
    await Future.delayed(Duration(milliseconds: 500));

    // List files
    List<File> files = [];
    
    // Check multiple possible locations
    final locations = <Directory?>[];
    if (Platform.isAndroid) {
      locations.add(Directory("/storage/emulated/0/Download"));
      locations.add(Directory("/storage/emulated/0/Downloads"));
      locations.add(Directory("/storage/self/primary/Download"));
      locations.add(Directory("/storage/self/primary/Downloads"));
      locations.add(Directory("/sdcard/Download"));
      locations.add(Directory("/sdcard/Downloads"));
      locations.add(await getExternalStorageDirectory());
    }
    locations.add(await getApplicationDocumentsDirectory());

    for (var dir in locations) {
      if (dir != null && await dir.exists()) {
        try {
          final dirFiles = dir.listSync()
            .whereType<File>()
            .where((f) => f.path.contains("flauncher_backup_") && f.path.endsWith(".json"))
            .toList();
          files.addAll(dirFiles);
        } catch (e) {
          debugPrint("Error listing files in ${dir.path}: $e");
        }
      }
    }

    // Sort by date desc
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No backups found")));
      return;
    }

    final file = await showDialog<File>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Select Backup"),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: files.length,
            itemBuilder: (c, i) {
              final f = files[i];
              final name = f.path.split("/").last;
              return ListTile(
                title: Text(name),
                subtitle: Text(f.statSync().modified.toString()),
                onTap: () => Navigator.pop(ctx, f as File),
              );
            },
          ),
        ),
      ),
    );

    if (file != null) {
      _restoreBackup(file);
    }
  }

  Future<void> _restoreBackupContent(String content) async {
    setState(() {
      _loading = true;
      _status = "Restoring backup...";
    });

    try {
      final db = Provider.of<FLauncherDatabase>(context, listen: false);
      final settings = Provider.of<SettingsService>(context, listen: false);
      final service = BackupService(db, settings);
      final missingApps = await service.restoreBackupFromContent(content);

      setState(() {
        _loading = false;
      });
      
      if (missingApps.isNotEmpty) {
        _installMissingApps(missingApps);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Restore completed successfully")));
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _restoreBackup(File file) async {
    setState(() {
      _loading = true;
      _status = "Restoring backup...";
    });

    try {
      final db = Provider.of<FLauncherDatabase>(context, listen: false);
      final settings = Provider.of<SettingsService>(context, listen: false);
      final service = BackupService(db, settings);
      final missingApps = await service.restoreBackup(file);

      setState(() {
        _loading = false;
      });
      
      if (missingApps.isNotEmpty) {
        _installMissingApps(missingApps);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Restore completed successfully")));
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _installMissingApps(List<AppSpec> apps) async {
    final installService = Provider.of<AppInstallService>(context, listen: false);
    final appsService = Provider.of<AppsService>(context, listen: false);
    await installService.checkAndRequestPermission();
    
    for (var i = 0; i < apps.length; i++) {
      final app = apps[i];
      
      final shouldInstall = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text("Restore App (${i+1}/${apps.length})"),
          content: Text("Do you want to install ${app.name}?"),
          actions: [
            TextButton(
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

      if (shouldInstall == true) {
        installService.startInstall(app);
        
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _InstallProgressDialog(
            app: app, 
            packageStream: appsService.packageAddedStream,
          ),
        );
      } else {
        // User skipped installation, remove from database so it doesn't show up
         try {
           final db = Provider.of<FLauncherDatabase>(context, listen: false);
           if (app.packageName != null) {
             await db.deleteApps([app.packageName!]);
           }
         } catch (e) {
           debugPrint("Error removing skipped app ${app.packageName}: $e");
         }
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("App restoration completed")));
  }
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
  bool _installed = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.packageStream.listen((packageName) {
      if (packageName == widget.app.packageName) {
        setState(() {
          _installed = true;
        });
        // Auto-close after a brief delay to let user see "Installed!"
        Future.delayed(Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
              child: Text(_installed ? "Next" : "Done"),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }
}
