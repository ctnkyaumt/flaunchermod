import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSpec {
  final String name;
  final String? packageName;
  final List<String> sources;

  AppSpec({
    required this.name,
    required this.sources,
    this.packageName,
  });
}

class AppInstallService extends ChangeNotifier {
  final FLauncherChannel _channel = FLauncherChannel();
  final SharedPreferences _prefs;

  final Map<String, String> _status = {};
  final Map<String, double> _progress = {};
  String? _activeAppName;

  Map<String, String> get status => _status;
  Map<String, double> get progress => _progress;
  String? get activeAppName => _activeAppName;

  static const String _kIsInstallingKey = "is_installing_apps_flow";
  static const String _kHasRequestedPermissionKey = "has_requested_install_permission";

  AppInstallService(this._prefs);

  bool get isInstallingFlow => _prefs.getBool(_kIsInstallingKey) ?? false;

  void setInstallingFlow(bool value) {
    _prefs.setBool(_kIsInstallingKey, value);
  }

  Future<void> checkAndRequestPermission() async {
    final hasRequested = _prefs.getBool(_kHasRequestedPermissionKey) ?? false;
    if (hasRequested) return;

    final canRequest = await _channel.canRequestPackageInstalls();
    if (!canRequest) {
      await _prefs.setBool(_kHasRequestedPermissionKey, true);
      setInstallingFlow(true);
      await _channel.requestPackageInstallsPermission();
    }
  }

  Future<void> startInstall(AppSpec app) async {
    if (_activeAppName != null) return;
    
    _activeAppName = app.name;
    _status[app.name] = "Preparing…";
    _progress[app.name] = 0.0;
    notifyListeners();

    try {
      await _installAppSpec(app);
    } catch (e) {
      _status[app.name] = "Error: $e";
    } finally {
      _activeAppName = null;
      notifyListeners();
    }
  }

  Future<String?> _installAppSpec(AppSpec app) async {
    final name = app.name;
    
    // Permission check first!
    final canRequest = await _channel.canRequestPackageInstalls();
    if (!canRequest) {
      _status[name] = "Waiting for permission…";
      notifyListeners();
      setInstallingFlow(true);
      final requested = await _channel.requestPackageInstallsPermission();
      if (requested) {
        // If we requested permission, we might get killed. 
        // If not killed, we might need to wait or just return.
        // For now, let's stop and let user retry after permission grant.
         _status[name] = "Permission requested. Retry after granting.";
         return "permission_requested";
      }
    }

    try {
      for (int i = 0; i < app.sources.length; i++) {
        final source = app.sources[i];

        _status[name] = "Resolving link… (${i + 1}/${app.sources.length})";
        _progress[name] = 0.0;
        notifyListeners();

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

        _status[name] = "Downloading… (${i + 1}/${app.sources.length})";
        notifyListeners();

        final file = await _downloadApk(name, downloadUrl);
        if (file == null) {
          continue;
        }

        _status[name] = "Opening installer…";
        notifyListeners();
        
        final installResult = await _channel.installApk(file.path);

        if (installResult == "started" || installResult == "silent_started") {
           _status[name] = "Installing…";
           // Cleanup later
          Future.delayed(Duration(minutes: 15), () async {
            try {
              if (await file.exists()) {
                await file.delete();
              }
            } catch (_) {}
          });
          return "started";
        } else if (installResult == "needs_permission") {
           _status[name] = "Permission needed";
           setInstallingFlow(true);
           // Logic handled by native side mostly, but we set flag just in case
        } else {
           // Failed, delete file
          try {
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
        }
      }
      
      _status[name] = "Installation failed";
      return null;

    } catch (e) {
      _status[name] = "Error: $e";
      rethrow;
    }
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
    if (token == "STREMIO") {
      return _getStremioApk();
    }
    return token;
  }

  Future<String?> _getStremioApk() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse("https://www.stremio.com/downloads"));
      request.headers.set(HttpHeaders.userAgentHeader, "FLauncher");
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final html = await response.transform(utf8.decoder).join();

      // Find "Stremio for Android TV" section to ensure we get the TV version
      // The user mentioned the 4th child div, which likely corresponds to the TV section.
      // We'll search for the section header or just look for links that look like TV versions if possible.
      // But Stremio APK names for TV usually contain "com.stremio.one" (same as mobile) but might be distinct builds.
      // The site usually separates them.
      
      final tvIndex = html.indexOf("Stremio for Android TV");
      final searchContext = tvIndex != -1 ? html.substring(tvIndex) : html;

      final matches = RegExp(r'''href=["'](https://[^"']+\.apk)["']''', caseSensitive: false).allMatches(searchContext);
      final urls = matches.map((m) => m.group(1)!).toList();

      if (urls.isEmpty) return null;

      final isArm64 = _isArm64();
      
      // Filter for architecture
      if (isArm64) {
        // Look for arm64/v8a
        return urls.firstWhere(
          (u) => u.toLowerCase().contains("arm64") || u.toLowerCase().contains("v8a"),
          orElse: () => urls.first, // Fallback
        );
      } else {
        // Look for armeabi/v7a
        return urls.firstWhere(
          (u) => u.toLowerCase().contains("armeabi") || u.toLowerCase().contains("v7a"),
          orElse: () => urls.first, // Fallback
        );
      }
    } catch (_) {
      return null;
    }
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
      if (total > 0) {
        _progress[name] = received / total;
        notifyListeners();
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
}
