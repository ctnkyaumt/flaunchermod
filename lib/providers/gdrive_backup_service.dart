import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';

class GDriveDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final String? verificationUrlComplete;
  final int expiresInSeconds;
  final int intervalSeconds;

  GDriveDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.verificationUrlComplete,
    required this.expiresInSeconds,
    required this.intervalSeconds,
  });
}

class GDriveFileInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;

  GDriveFileInfo({required this.id, required this.name, required this.modifiedTime});
}

class GDriveBackupService {
  static const _deviceCodeUrl = 'https://oauth2.googleapis.com/device/code';
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _driveFilesUrl = 'https://www.googleapis.com/drive/v3/files';
  static const _driveUploadUrl = 'https://www.googleapis.com/upload/drive/v3/files';
  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';

  final SettingsService _settings;
  final HttpClient _client = HttpClient();

  GDriveBackupService(this._settings);

  String? get clientId => _settings.gDriveClientId;

  bool get isSignedIn => (_settings.gDriveRefreshToken ?? '').isNotEmpty;

  Future<void> setClientId(String clientId) => _settings.setGDriveClientId(clientId);

  Future<void> signOut() async {
    await _settings.clearGDriveAuth();
  }

  Future<GDriveDeviceCode> startDeviceCodeFlow() async {
    final cid = clientId;
    if (cid == null || cid.trim().isEmpty) {
      throw Exception('Google OAuth client id is not set');
    }

    final body = <String, String>{
      'client_id': cid,
      'scope': _scope,
    };

    final response = await _postFormJson(Uri.parse(_deviceCodeUrl), body);
    return GDriveDeviceCode(
      deviceCode: response['device_code'] as String,
      userCode: response['user_code'] as String,
      verificationUrl: (response['verification_url'] ?? response['verification_uri']) as String,
      verificationUrlComplete: (response['verification_url_complete'] ?? response['verification_uri_complete']) as String?,
      expiresInSeconds: (response['expires_in'] as num).toInt(),
      intervalSeconds: ((response['interval'] as num?)?.toInt() ?? 5),
    );
  }

  Future<void> pollAndSaveTokens({
    required GDriveDeviceCode deviceCode,
    required bool Function() isCancelled,
  }) async {
    final cid = clientId;
    if (cid == null || cid.trim().isEmpty) {
      throw Exception('Google OAuth client id is not set');
    }

    final deadline = DateTime.now().add(Duration(seconds: deviceCode.expiresInSeconds));
    var interval = deviceCode.intervalSeconds;

    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled()) {
        throw Exception('Sign-in cancelled');
      }

      final body = <String, String>{
        'client_id': cid,
        'device_code': deviceCode.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      };

      final tokenResponse = await _postFormJson(Uri.parse(_tokenUrl), body, allowErrorResponse: true);
      if (tokenResponse.containsKey('error')) {
        final error = tokenResponse['error']?.toString() ?? 'unknown_error';
        if (error == 'authorization_pending') {
          await Future.delayed(Duration(seconds: interval));
          continue;
        }
        if (error == 'slow_down') {
          interval += 5;
          await Future.delayed(Duration(seconds: interval));
          continue;
        }
        throw Exception('Sign-in failed: $error');
      }

      final accessToken = tokenResponse['access_token']?.toString();
      final refreshToken = tokenResponse['refresh_token']?.toString();
      final expiresIn = (tokenResponse['expires_in'] as num?)?.toInt() ?? 3600;

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Sign-in failed: access token missing');
      }

      await _settings.setGDriveAccessToken(accessToken, DateTime.now().add(Duration(seconds: expiresIn)));

      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _settings.setGDriveRefreshToken(refreshToken);
      }

      return;
    }

    throw Exception('Sign-in timed out');
  }

  Future<String> _getValidAccessToken() async {
    final cid = clientId;
    if (cid == null || cid.trim().isEmpty) {
      throw Exception('Google OAuth client id is not set');
    }

    final access = _settings.gDriveAccessToken;
    final expiry = _settings.gDriveAccessTokenExpiry;
    final now = DateTime.now();
    if (access != null && access.isNotEmpty && expiry != null && expiry.isAfter(now.add(Duration(seconds: 30)))) {
      return access;
    }

    final refresh = _settings.gDriveRefreshToken;
    if (refresh == null || refresh.isEmpty) {
      throw Exception('Not signed in');
    }

    final body = <String, String>{
      'client_id': cid,
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    };

    final tokenResponse = await _postFormJson(Uri.parse(_tokenUrl), body, allowErrorResponse: true);
    if (tokenResponse.containsKey('error')) {
      final err = tokenResponse['error']?.toString() ?? 'unknown_error';
      throw Exception('Token refresh failed: $err');
    }

    final accessToken = tokenResponse['access_token']?.toString();
    final expiresIn = (tokenResponse['expires_in'] as num?)?.toInt() ?? 3600;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Token refresh failed: access token missing');
    }

    final expiryAt = DateTime.now().add(Duration(seconds: expiresIn));
    await _settings.setGDriveAccessToken(accessToken, expiryAt);
    return accessToken;
  }

  Future<GDriveFileInfo> uploadBackupJson({
    required String fileName,
    required String content,
  }) async {
    final token = await _getValidAccessToken();

    final boundary = 'flauncher_${DateTime.now().millisecondsSinceEpoch}';
    final metadata = {
      'name': fileName,
      'parents': ['appDataFolder'],
    };

    final bodyBytes = _buildMultipartRelated(
      boundary: boundary,
      metadataJson: jsonEncode(metadata),
      fileBytes: utf8.encode(content),
      fileContentType: 'application/json',
    );

    final uri = Uri.parse('$_driveUploadUrl?uploadType=multipart&fields=id,name,modifiedTime');
    final req = await _client.postUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    req.headers.set(HttpHeaders.contentTypeHeader, 'multipart/related; boundary=$boundary');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.add(bodyBytes);

    final res = await req.close();
    final resBody = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Upload failed: HTTP ${res.statusCode} $resBody');
    }

    final data = jsonDecode(resBody);
    if (data is! Map) {
      throw Exception('Upload failed: invalid response');
    }

    final id = data['id']?.toString();
    final name = data['name']?.toString() ?? fileName;
    final modifiedTimeStr = data['modifiedTime']?.toString();
    return GDriveFileInfo(
      id: id ?? '',
      name: name,
      modifiedTime: modifiedTimeStr == null ? null : DateTime.tryParse(modifiedTimeStr),
    );
  }

  Future<List<GDriveFileInfo>> listBackups({required int maxResults}) async {
    final token = await _getValidAccessToken();
    final q = "name contains 'flauncher_backup_' and trashed=false";
    final uri = Uri.parse(_driveFilesUrl).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'orderBy': 'modifiedTime desc',
      'pageSize': '$maxResults',
      'fields': 'files(id,name,modifiedTime)',
      'q': q,
    });

    final req = await _client.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final res = await req.close();
    final resBody = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('List failed: HTTP ${res.statusCode} $resBody');
    }

    final data = jsonDecode(resBody);
    if (data is! Map) return [];
    final files = data['files'];
    if (files is! List) return [];

    return files.whereType<Map>().map((f) {
      final id = f['id']?.toString() ?? '';
      final name = f['name']?.toString() ?? '';
      final modified = f['modifiedTime']?.toString();
      return GDriveFileInfo(
        id: id,
        name: name,
        modifiedTime: modified == null ? null : DateTime.tryParse(modified),
      );
    }).where((f) => f.id.isNotEmpty).toList();
  }

  Future<String> downloadBackupContent(String fileId) async {
    final token = await _getValidAccessToken();
    final uri = Uri.parse('$_driveFilesUrl/$fileId').replace(queryParameters: {'alt': 'media'});
    final req = await _client.getUrl(uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final res = await req.close();
    final bytes = await res.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = utf8.decode(bytes, allowMalformed: true);
      throw Exception('Download failed: HTTP ${res.statusCode} $body');
    }
    return utf8.decode(bytes);
  }

  List<int> _buildMultipartRelated({
    required String boundary,
    required String metadataJson,
    required List<int> fileBytes,
    required String fileContentType,
  }) {
    final crlf = '\r\n';
    final parts = <List<int>>[];

    parts.add(utf8.encode('--$boundary$crlf'));
    parts.add(utf8.encode('Content-Type: application/json; charset=UTF-8$crlf$crlf'));
    parts.add(utf8.encode(metadataJson));
    parts.add(utf8.encode(crlf));

    parts.add(utf8.encode('--$boundary$crlf'));
    parts.add(utf8.encode('Content-Type: $fileContentType$crlf$crlf'));
    parts.add(fileBytes);
    parts.add(utf8.encode(crlf));

    parts.add(utf8.encode('--$boundary--$crlf'));

    final out = <int>[];
    for (final p in parts) {
      out.addAll(p);
    }
    return out;
  }

  Future<Map<String, dynamic>> _postFormJson(
    Uri uri,
    Map<String, String> form, {
    bool allowErrorResponse = false,
  }) async {
    final req = await _client.postUrl(uri);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.write(Uri(queryParameters: form).query);

    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (!allowErrorResponse && (res.statusCode < 200 || res.statusCode >= 300)) {
      throw Exception('HTTP ${res.statusCode} $body');
    }
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }
}

