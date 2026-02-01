import 'dart:io';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class InstallAppsPanelPage extends StatefulWidget {
  static const String routeName = "install_apps_panel";

  @override
  _InstallAppsPanelPageState createState() => _InstallAppsPanelPageState();
}

class _InstallAppsPanelPageState extends State<InstallAppsPanelPage> {
  final Map<String, String> _apps = {
    "SmartTube": "https://github.com/yuliskov/SmartTube/releases/download/latest/smarttube_stable.apk",
    "Stremio": "STREMIO_PLACEHOLDER",
    "AnExplorer": "https://d.apkpure.com/b/APK/dev.dworks.apps.anexplorer?version=latest",
    "Blackbulb": "https://github.com/ctnkyaumt/Blackbulb/releases/download/v2.2.1/app-release-unsigned.apk"
  };

  final Map<String, String> _status = {};
  final Map<String, double> _progress = {};

  @override
  void initState() {
    super.initState();
    _apps.keys.forEach((app) {
      _status[app] = "Idle";
      _progress[app] = 0.0;
    });
  }

  Future<String?> _getStremioLink() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse("https://www.stremio.com/downloads"));
      final response = await request.close();
      final html = await response.transform(SystemEncoding().decoder).join();
      
      // Look for Android TV section
      // The user mentioned: #downloads-table > div > div:nth-child(4) > div.table-body-cell.other-download-links.text-left > a:nth-child(1)
      // This implies it is inside #downloads-table
      
      // Simple heuristic: Find "Android TV" and then the first .apk link after it.
      // Or look for specific Stremio apk naming pattern.
      
      // Let's try to find the specific structure roughly.
      // We can split by "Android TV"
      final parts = html.split("Android TV");
      if (parts.length > 1) {
        // Look in the part after "Android TV"
        final section = parts[1];
        // Find href="...apk"
        final regExp = RegExp(r'href="([^"]+\.apk)"');
        final match = regExp.firstMatch(section);
        if (match != null) {
          return match.group(1);
        }
      }
      
      // Fallback: search whole page for stremio...arm...apk
      final regExpFallback = RegExp(r'href="([^"]+stremio[^"]+arm[^"]+\.apk)"');
      final matchFallback = regExpFallback.firstMatch(html);
      if (matchFallback != null) {
        return matchFallback.group(1);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _installApp(String name, String url) async {
    setState(() {
      _status[name] = "Downloading...";
      _progress[name] = 0.0;
    });

    try {
      String downloadUrl = url;
      if (url == "STREMIO_PLACEHOLDER") {
        setState(() => _status[name] = "Fetching link...");
        final link = await _getStremioLink();
        if (link == null) {
          throw Exception("Could not find Stremio link");
        }
        downloadUrl = link;
        if (!downloadUrl.startsWith("http")) {
            if (downloadUrl.startsWith("//")) {
                downloadUrl = "https:$downloadUrl";
            } else if (downloadUrl.startsWith("/")) {
                downloadUrl = "https://www.stremio.com$downloadUrl";
            }
        }
        setState(() => _status[name] = "Downloading...");
      }

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception("Download failed (${response.statusCode})");
      }
      
      final dir = await getTemporaryDirectory();
      // sanitize filename
      final fileName = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final file = File('${dir.path}/$fileName.apk');
      final sink = file.openWrite();
      
      final total = response.contentLength;
      int received = 0;
      
      await response.listen((data) {
        sink.add(data);
        received += data.length;
        if (total > 0 && mounted) {
            setState(() => _progress[name] = received / total);
        }
      }).asFuture();
      
      await sink.close();
      
      if (!mounted) return;

      setState(() => _status[name] = "Opening installer...");
      final installResult = await FLauncherChannel().installApk(file.path);
      
      // Wait a bit before deleting to allow Intent to read it
      if (installResult == "started") {
        Future.delayed(Duration(minutes: 15), () async {
          if (await file.exists()) {
            await file.delete();
          }
        });
      }

      if (!mounted) return;

      setState(() {
        if (installResult == "started") {
          _status[name] = "Installer opened";
        } else if (installResult == "needs_permission") {
          _status[name] = "Allow 'Install unknown apps', then tap again";
        } else if (installResult == "missing_manifest_permission") {
          _status[name] = "App missing install permission (rebuild/reinstall)";
        } else {
          _status[name] = "Failed to start installer";
        }
        _progress[name] = 1.0;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status[name] = "Error: $e";
        _progress[name] = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("Install Apps", style: Theme.of(context).textTheme.titleLarge),
        Divider(),
        Expanded(
          child: ListView.builder(
            itemCount: _apps.length,
            itemBuilder: (context, index) {
              final name = _apps.keys.elementAt(index);
              final url = _apps[name]!;
              return EnsureVisible(
                alignment: 0.5,
                child: Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_status[name] ?? ""),
                        if (_status[name] == "Downloading...")
                          LinearProgressIndicator(value: _progress[name]),
                      ],
                    ),
                    trailing: ElevatedButton(
                      child: Text("Install"),
                      onPressed: (_status[name] == "Downloading..." || _status[name] == "Installing...")
                          ? null
                          : () => _installApp(name, url),
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
