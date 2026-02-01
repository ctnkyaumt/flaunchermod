import 'dart:convert';
import 'dart:ffi';
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
    "Stremio": "STREMIO",
    "X-Plore": "https://mobdisc.com/fdl/7a6d5bea-1458-49df-ade3-f4f4fbebfeb3/X-plore-Donate-v4-45-02.apk",
    "AnExplorer": "https://mobdisc.com/fdl/680789f3-ac9c-4885-959d-1b2c2be0cc60/AnExplorer-Pro-v5-7-4.apk",
    "Fluffy File Manager": "GITHUB:mlm-games/Fluffy",
    "Kodi": "KODI",
    "Cloudstream": "GITHUB:recloudstream/cloudstream",
    "Blackbulb": "GITHUB:ctnkyaumt/Blackbulb",
    "Tivimate": "TIVIMATE",
  };

  final Map<String, String> _status = {};
  final Map<String, double> _progress = {};
  bool _installAllInProgress = false;
  int _installAllNextIndex = 0;

  @override
  void initState() {
    super.initState();
    _apps.keys.forEach((app) {
      _status[app] = "Idle";
      _progress[app] = 0.0;
    });
  }

  bool _isArm64() {
    try {
      return Abi.current() == Abi.androidArm64;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _getStremioLink() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse("https://www.stremio.com/downloads"));
      final response = await request.close();
      final html = await response.transform(SystemEncoding().decoder).join();

      final blocks = RegExp(
        r'<div class="table-body-cell other-download-links text-left">([\s\S]*?)</div>',
        caseSensitive: false,
      ).allMatches(html).map((m) => m.group(1) ?? "").toList();

      if (blocks.length >= 4) {
        final block = blocks[3];
        final links = RegExp(r'href="([^"]+)"', caseSensitive: false)
            .allMatches(block)
            .map((m) => m.group(1))
            .whereType<String>()
            .toList();

        final index = _isArm64() ? 4 : 0;
        if (links.length > index) {
          return links[index];
        }
      }

      final regExpFallback = RegExp(r'href="([^"]+\.apk[^"]*)"', caseSensitive: false);
      final matchFallback = regExpFallback.firstMatch(html);
      if (matchFallback != null) return matchFallback.group(1);

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getTivimateLink() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse("https://tivimate.com/"));
      final response = await request.close();
      final html = await response.transform(SystemEncoding().decoder).join();

      final apkMatch = RegExp("(https?://[^\"']+\\.apk[^\"']*)", caseSensitive: false).firstMatch(html);
      if (apkMatch != null) return apkMatch.group(1);

      final hrefMatch = RegExp(r'href="([^"]+\.apk[^"]*)"', caseSensitive: false).firstMatch(html);
      if (hrefMatch != null) {
        final href = hrefMatch.group(1);
        if (href == null) return null;
        if (href.startsWith("http")) return href;
        if (href.startsWith("//")) return "https:$href";
        if (href.startsWith("/")) return "https://tivimate.com$href";
        return "https://tivimate.com/$href";
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getGithubLatestApk(String ownerRepo) async {
    try {
      final uri = Uri.parse("https://api.github.com/repos/$ownerRepo/releases/latest");
      final client = HttpClient();
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, "FLauncher");
      request.headers.set(HttpHeaders.acceptHeader, "application/vnd.github+json");
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map) return null;

      final assets = data["assets"];
      if (assets is! List) return null;

      final urls = assets
          .whereType<Map>()
          .map((a) => a["browser_download_url"])
          .whereType<String>()
          .where((u) => u.toLowerCase().contains(".apk"))
          .toList();

      if (urls.isEmpty) return null;

      final isArm64 = _isArm64();
      final preferred = urls.firstWhere(
        (u) {
          final s = u.toLowerCase();
          if (isArm64) return s.contains("arm64") || s.contains("v8a");
          return s.contains("armeabi") || s.contains("v7a") || s.contains("armv7");
        },
        orElse: () => urls.first,
      );

      return preferred;
    } catch (_) {
      return null;
    }
  }

  String _getKodiUrl() {
    if (_isArm64()) {
      return "https://mirrors.kodi.tv/releases/android/arm64-v8a/kodi-21.3-Omega-arm64-v8a.apk?https=1";
    }
    return "https://mirrors.kodi.tv/releases/android/arm/kodi-21.3-Omega-armeabi-v7a.apk?https=1";
  }

  Future<String?> _resolveUrl(String token) async {
    if (token == "STREMIO") return _getStremioLink();
    if (token == "KODI") return _getKodiUrl();
    if (token == "TIVIMATE") return _getTivimateLink();
    if (token.startsWith("GITHUB:")) return _getGithubLatestApk(token.substring("GITHUB:".length));
    return token;
  }

  Future<String?> _installApp(String name, String url) async {
    setState(() {
      _status[name] = "Preparing...";
      _progress[name] = 0.0;
    });

    try {
      setState(() => _status[name] = "Resolving link...");
      final resolved = await _resolveUrl(url);
      if (resolved == null) {
        throw Exception("Could not resolve download link");
      }

      String downloadUrl = resolved;
      if (!downloadUrl.startsWith("http")) {
        if (downloadUrl.startsWith("//")) {
          downloadUrl = "https:$downloadUrl";
        } else if (downloadUrl.startsWith("/")) {
          downloadUrl = "https://www.stremio.com$downloadUrl";
        }
      }

      setState(() => _status[name] = "Downloading...");

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
      
      if (!mounted) return null;

      setState(() => _status[name] = "Opening installer...");
      final installResult = await FLauncherChannel().installApk(file.path);
      
      // Wait a bit before deleting to allow Intent to read it
      if (installResult == "started" || installResult == "silent_started") {
        Future.delayed(Duration(minutes: 15), () async {
          if (await file.exists()) {
            await file.delete();
          }
        });
      }

      if (!mounted) return null;

      setState(() {
        if (installResult == "silent_started") {
          _status[name] = "Install requested";
        } else if (installResult == "started") {
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

      return installResult;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _status[name] = "Error: $e";
        _progress[name] = 0.0;
      });
      return null;
    }
  }

  Future<void> _installAll() async {
    if (_installAllInProgress) return;

    setState(() {
      _installAllInProgress = true;
    });

    final entries = _apps.entries.toList();
    for (var i = _installAllNextIndex; i < entries.length; i++) {
      if (!mounted) return;

      final entry = entries[i];
      final name = entry.key;
      final url = entry.value;

      final result = await _installApp(name, url);
      _installAllNextIndex = i + 1;

      if (!mounted) return;

      if (result == "started" || result == "needs_permission") {
        setState(() {
          _installAllInProgress = false;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _installAllInProgress = false;
      _installAllNextIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text("Install Apps", style: Theme.of(context).textTheme.titleLarge),
              ),
              ElevatedButton(
                onPressed: _installAllInProgress ? null : _installAll,
                child: Text(_installAllNextIndex == 0 ? "Install All" : "Install All (${_installAllNextIndex}/${_apps.length})"),
              ),
            ],
          ),
        ),
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
                      onPressed: (_status[name] == "Downloading..." ||
                              _status[name] == "Resolving link..." ||
                              _status[name] == "Preparing..." ||
                              _status[name] == "Opening installer..." ||
                              _installAllInProgress)
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
