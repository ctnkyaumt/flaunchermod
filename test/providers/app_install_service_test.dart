/*
 * FLaunchermod
 * originally by efesser (30 May 2021)
 * ctnkyaumt 2026
 * Copyright (C) 2021 Étienne Fesser
 * Copyright (C) 2026 ctnkyaumt
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late Directory downloads;
  late _PackageInstaller installer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    downloads = await Directory.systemTemp.createTemp('flauncher_install_test');
    installer = _PackageInstaller();
  });
  tearDown(() => downloads.delete(recursive: true));

  AppInstallService installingFrom(Map<String, _Source> sources) => AppInstallService(
        preferences,
        channel: installer,
        httpClient: () => _Internet(sources),
        temporaryDirectory: () async => downloads,
        networkTimeout: const Duration(milliseconds: 200),
      );

  test('an app is installed from the next source when the first cannot be reached', () async {
    final service = installingFrom({
      'down.test': _Source.unreachable(),
      'up.test': _Source.serving('PK from the second source'),
    });

    await service.startInstall(AppSpec(
      name: 'Player',
      sources: ['https://down.test/player.apk', 'https://up.test/player.apk'],
    ));

    expect(installer.installed, ['PK from the second source']);
    expect(service.status['Player'], 'Installing…');
    service.dispose();
  });

  test('a source that goes silent mid-download does not block the next install', () async {
    final service = installingFrom({
      'silent.test': _Source.goingSilentAfter('PK half of'),
      'up.test': _Source.serving('PK another app'),
    });

    await service.startInstall(AppSpec(name: 'Stuck', sources: ['https://silent.test/stuck.apk']));
    expect(service.status['Stuck'], 'Installation failed');
    expect(service.activeAppName, isNull);

    await service.startInstall(AppSpec(name: 'Other', sources: ['https://up.test/other.apk']));

    expect(installer.installed, ['PK another app']);
    service.dispose();
  });
}

/// Stands in for Android's package installer on the other side of the channel.
class _PackageInstaller extends FLauncherChannel {
  /// The contents of every APK handed over for installation.
  final installed = <String>[];

  @override
  Future<bool> canRequestPackageInstalls() async => true;

  @override
  Future<String?> installApk(String filePath) async {
    installed.add(await File(filePath).readAsString());
    return 'started';
  }
}

/// What one host answers; an APK is recognised by its leading "PK".
class _Source {
  final bool reachable;
  final String body;
  final bool endsBody;

  _Source.unreachable()
      : reachable = false,
        body = '',
        endsBody = true;
  _Source.serving(this.body)
      : reachable = true,
        endsBody = true;
  _Source.goingSilentAfter(this.body)
      : reachable = true,
        endsBody = false;
}

class _Internet implements HttpClient {
  final Map<String, _Source> sources;

  _Internet(this.sources);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final source = sources[url.host]!;
    if (!source.reachable) {
      throw const SocketException('Connection refused');
    }
    return _Request(source);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  final _Source source;

  _Request(this.source);

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _Response(source);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  ContentType? get contentType => null;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  final _Source source;

  _Response(this.source);

  @override
  int get statusCode => 200;

  @override
  int get contentLength => source.endsBody ? utf8.encode(source.body).length : -1;

  @override
  HttpHeaders get headers => _Headers();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final body = StreamController<List<int>>();
    body.add(utf8.encode(source.body));
    if (source.endsBody) {
      body.close();
    }
    return body.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
