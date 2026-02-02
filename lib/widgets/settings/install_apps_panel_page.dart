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

class _AppSpec {
  final String name;
  final String? packageName;
  final List<String> sources;

  _AppSpec({
    required this.name,
    required this.sources,
    this.packageName,
  });
}

class _InstallAppsPanelPageState extends State<InstallAppsPanelPage> {
  final List<_AppSpec> _apps = [
    _AppSpec(
      name: "SmartTube",
      packageName: "com.teamsmart.videomanager.tv",
      sources: ["https://github.com/yuliskov/SmartTube/releases/download/latest/smarttube_stable.apk"],
    ),
    _AppSpec(
      name: "Stremio",
      packageName: "com.stremio.one",
      sources: [
        "APKPURE:com.stremio.one",
        "APKCOMBO:com.stremio.one",
        "APKPREMIER:com.stremio.one",
        "APKSUPPORT:com.stremio.one",
      ],
    ),
    _AppSpec(
      name: "FX File Manager",
      packageName: "nextapp.fx",
      sources: [
        "APKPURE:nextapp.fx",
        "APKCOMBO:nextapp.fx",
        "APKPREMIER:nextapp.fx",
        "APKSUPPORT:nextapp.fx",
      ],
    ),
    _AppSpec(
      name: "Total Commander",
      packageName: "com.ghisler.android.TotalCommander",
      sources: [
        "APKPURE:com.ghisler.android.TotalCommander",
        "APKCOMBO:com.ghisler.android.TotalCommander",
        "APKPREMIER:com.ghisler.android.TotalCommander",
        "APKSUPPORT:com.ghisler.android.TotalCommander",
      ],
    ),
    _AppSpec(
      name: "Kodi",
      packageName: "org.xbmc.kodi",
      sources: ["KODI"],
    ),
    _AppSpec(
      name: "Cloudstream",
      packageName: "com.lagradost.cloudstream3",
      sources: ["GITHUB:recloudstream/cloudstream"],
    ),
    _AppSpec(
      name: "Blackbulb",
      packageName: "info.papdt.blackblub",
      sources: ["GITHUB:ctnkyaumt/Blackbulb"],
    ),
    _AppSpec(
      name: "Sparkle",
      packageName: "se.hedekonsult.sparkle",
      sources: ["https://github.com/ctnkyaumt/test/blob/main/sitv/sitv.apk"],
    ),
    _AppSpec(
      name: "AnExplorer",
      packageName: "dev.dworks.apps.anexplorer.pro",
      sources: ["https://github.com/ctnkyaumt/test/blob/main/anexp/anexp.apk"],
    ),
  ];

  final Map<String, String> _status = {};
  final Map<String, double> _progress = {};
  final Set<String> _installedPackages = {};
  final Set<String> _installedAppNames = {};
  String? _activeAppName;

  @override
  void initState() {
    super.initState();
    for (final app in _apps) {
      _status[app.name] = "Idle";
      _progress[app.name] = 0.0;
    }
    _refreshInstalledPackages();
  }

  bool _isInstalled(_AppSpec app) {
    final packageName = app.packageName;
    if (packageName == null) return false;
    return _installedPackages.contains(packageName);
  }

  bool _isInstalledByName(_AppSpec app) => _installedAppNames.contains(app.name);

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
            _status[app.name] = "Already installed";
            _progress[app.name] = 1.0;
          } else if (_status[app.name] == "Already installed") {
            _status[app.name] = "Idle";
            _progress[app.name] = 0.0;
          }
        }
      });
    } catch (_) {}
  }

  bool _isArm64() {
    try {
      return Abi.current() == Abi.androidArm64;
    } catch (_) {
      return false;
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

  Future<String?> _getApkSupportDirectLink(String packageName) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse("https://apk.support/download-app/$packageName"));
      request.headers.set(HttpHeaders.userAgentHeader, "FLauncher");
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final html = await response.transform(utf8.decoder).join();
      final match = RegExp("(https?://[^\"']+\\.apk[^\"']*)", caseSensitive: false).firstMatch(html);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveUrl(String token) async {
    if (token == "KODI") return _getKodiUrl();
    if (token.startsWith("GITHUB:")) return _getGithubLatestApk(token.substring("GITHUB:".length));
    if (token.startsWith("https://github.com/") && token.contains("/blob/")) {
      final uri = Uri.parse(token);
      final parts = uri.pathSegments;
      final blobIndex = parts.indexOf("blob");
      if (blobIndex > 1 && parts.length > blobIndex + 1) {
        final owner = parts[0];
        final repo = parts[1];
        final branch = parts[blobIndex + 1];
        final filePath = parts.sublist(blobIndex + 2).join("/");
        return "https://raw.githubusercontent.com/$owner/$repo/$branch/$filePath";
      }
    }
    if (token.startsWith("APKPURE:")) {
      final packageName = token.substring("APKPURE:".length);
      return "https://d.apkpure.com/b/APK/$packageName?version=latest";
    }
    if (token.startsWith("APKCOMBO:")) {
      final packageName = token.substring("APKCOMBO:".length);
      return "https://apkcombo.com/genericApp/$packageName/download/apk";
    }
    if (token.startsWith("APKPREMIER:")) {
      final packageName = token.substring("APKPREMIER:".length);
      return "https://apkpremier.com/download/${packageName.replaceAll('.', '-')}";
    }
    if (token.startsWith("APKSUPPORT:")) {
      final packageName = token.substring("APKSUPPORT:".length);
      final resolved = await _getApkSupportDirectLink(packageName);
      return resolved ?? "https://apk.support/download-app/$packageName";
    }
    return token;
  }

  Future<bool> _looksLikeApk(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(2);
      await raf.close();
      return bytes.length == 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    } catch (_) {
      return false;
    }
  }

  Future<File?> _downloadApk(String name, String downloadUrl, {int depth = 0}) async {
    if (depth > 2) return null;
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(downloadUrl));
    request.headers.set(HttpHeaders.userAgentHeader, "FLauncher");
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final mimeType = response.headers.contentType?.mimeType;
    if (mimeType == "text/html" || mimeType == "application/xhtml+xml") {
      final html = await response.transform(utf8.decoder).join();
      final match = RegExp("(https?://[^\"']+\\.apk[^\"']*)", caseSensitive: false).firstMatch(html);
      final nextUrl = match?.group(1);
      if (nextUrl == null) return null;
      return _downloadApk(name, nextUrl, depth: depth + 1);
    }

    final dir = await getTemporaryDirectory();
    final fileName = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final file = File('${dir.path}/$fileName-${DateTime.now().millisecondsSinceEpoch}.apk');
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

    final isApk = await _looksLikeApk(file);
    if (!isApk) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
    return file;
  }

  Future<String?> _installAppSpec(_AppSpec app) async {
    final name = app.name;
    if (_isInstalled(app)) {
      if (!mounted) return "already_installed";
      setState(() {
        _status[name] = "Already installed";
        _progress[name] = 1.0;
      });
      return "already_installed";
    }

    setState(() {
      _status[name] = "Preparing…";
      _progress[name] = 0.0;
    });

    try {
      for (int i = 0; i < app.sources.length; i++) {
        if (!mounted) return null;
        final source = app.sources[i];

        setState(() {
          _status[name] = "Resolving link… (${i + 1}/${app.sources.length})";
          _progress[name] = 0.0;
        });

        final resolved = await _resolveUrl(source);
        if (resolved == null) {
          continue;
        }

        var downloadUrl = resolved;
        if (!downloadUrl.startsWith("http")) {
          if (downloadUrl.startsWith("//")) {
            downloadUrl = "https:$downloadUrl";
          }
        }

        if (!mounted) return null;
        setState(() => _status[name] = "Downloading… (${i + 1}/${app.sources.length})");

        final file = await _downloadApk(name, downloadUrl);
        if (file == null) {
          continue;
        }

        if (!mounted) return null;
        setState(() => _status[name] = "Opening installer…");
        final installResult = await FLauncherChannel().installApk(file.path);

        if (installResult == "started" || installResult == "silent_started") {
          Future.delayed(Duration(minutes: 15), () async {
            try {
              if (await file.exists()) {
                await file.delete();
              }
            } catch (_) {}
          });
        } else {
          try {
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
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

        Future.delayed(Duration(seconds: 2), _refreshInstalledPackages);
        return installResult;
      }

      if (!mounted) return null;
      setState(() {
        _status[name] = "All sources failed";
        _progress[name] = 0.0;
      });
      return null;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _status[name] = "Error: $e";
        _progress[name] = 0.0;
      });
      return null;
    }
  }

  Future<void> _startInstall(_AppSpec app) async {
    if (_activeAppName != null) return;
    
    setState(() => _activeAppName = app.name);
    await _installAppSpec(app);
    await _refreshInstalledPackages();
    if (!mounted) return;
    setState(() => _activeAppName = null);
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
              final busy = _activeAppName == name ||
                  _status[name] == "Preparing…" ||
                  (_status[name]?.startsWith("Resolving link…") ?? false) ||
                  (_status[name]?.startsWith("Downloading…") ?? false) ||
                  _status[name] == "Opening installer…";
              final anyBusy = _activeAppName != null;

              final onPressed = (installed || anyBusy) ? null : () => _startInstall(app);
              final buttonText = installed
                  ? "Installed"
                  : busy
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
                        Text(_status[name] ?? ""),
                        if ((_status[name]?.startsWith("Downloading…") ?? false) && (_progress[name] ?? 0) > 0)
                          LinearProgressIndicator(value: _progress[name]),
                      ],
                    ),
                    trailing: ElevatedButton(
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
