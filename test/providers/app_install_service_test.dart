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

  test('downloaded APKs are saved in the apk_downloads folder of the temporary directory', () async {
    final service = installingFrom({'up.test': _Source.serving('PK player')});

    await service.startInstall(AppSpec(name: 'Player', sources: ['https://up.test/player.apk']));

    expect(installer.installed, ['PK player']);
    expect(File(installer.installedPaths.single).parent.path, '${downloads.path}/apk_downloads');
    service.dispose();
  });

  test('an install asked for while another runs waits for it, then runs to its own result', () async {
    final service = installingFrom({
      'first.test': _Source.serving('PK first'),
      'second.test': _Source.serving('PK second'),
    });
    final firstInstallerOpened = Completer<void>();
    installer.holdNextInstall = firstInstallerOpened;

    final first = service.startInstall(AppSpec(name: 'First', sources: ['https://first.test/first.apk']));
    var secondEnded = false;
    final second = service
        .startInstall(AppSpec(name: 'Second', sources: ['https://second.test/second.apk']))
        .then((_) => secondEnded = true);

    expect(service.status['Second'], 'Waiting for First…');
    await installer.installRequested.future;
    expect(service.status['Second'], 'Waiting for First…');
    expect(secondEnded, isFalse);

    firstInstallerOpened.complete();
    await first;
    await second;

    expect(installer.installed, ['PK first', 'PK second']);
    expect(service.status['First'], 'Installing…');
    expect(service.status['Second'], 'Installing…');
    expect(service.activeAppName, isNull);
    service.dispose();
  });

  group('reopening the Install panel on resume', () {
    final app = AppSpec(name: 'Player', sources: ['https://down.test/player.apk']);
    AppInstallService needingPermission() {
      installer.canInstall = false;
      return installingFrom({'down.test': _Source.unreachable()});
    }

    test('does not happen when this launcher opened the permission screen itself', () async {
      final service = needingPermission();
      await service.startInstall(app);
      expect(service.status['Player'], 'Permission requested. Retry after granting.');

      expect(service.consumeInstallPanelReopen(), isFalse);
      // The flag is gone: not even a restart reopens the panel now.
      expect(needingPermission().consumeInstallPanelReopen(), isFalse);
      service.dispose();
    });

    test('happens once after the launcher was restarted while the permission screen showed', () async {
      final killed = needingPermission();
      await killed.startInstall(app);

      final restarted = needingPermission();
      expect(restarted.consumeInstallPanelReopen(), isTrue);
      expect(restarted.consumeInstallPanelReopen(), isFalse);
      killed.dispose();
      restarted.dispose();
    });

    test('happens once after a restart when the installer itself sent the user to the permission screen', () async {
      installer.installAnswer = 'needs_permission';
      final killed = installingFrom({'up.test': _Source.serving('PK player')});
      await killed.startInstall(AppSpec(name: 'Player', sources: ['https://up.test/player.apk']));
      expect(killed.consumeInstallPanelReopen(), isFalse);
      await killed.startInstall(AppSpec(name: 'Player', sources: ['https://up.test/player.apk']));

      final restarted = installingFrom({});
      expect(restarted.consumeInstallPanelReopen(), isTrue);
      expect(restarted.consumeInstallPanelReopen(), isFalse);
      killed.dispose();
      restarted.dispose();
    });

    test('never happens when the permission screen could not be opened', () async {
      installer.permissionScreenOpens = false;
      final service = needingPermission();
      await service.startInstall(app);
      await service.checkAndRequestPermission();

      final restarted = needingPermission();
      expect(restarted.consumeInstallPanelReopen(), isFalse);
      service.dispose();
      restarted.dispose();
    });
  });
}

/// Stands in for Android's package installer on the other side of the channel.
class _PackageInstaller extends FLauncherChannel {
  /// The contents of every APK handed over for installation.
  final installed = <String>[];

  /// Where each of those APKs was.
  final installedPaths = <String>[];

  /// Completes when the first APK is handed over.
  final installRequested = Completer<void>();

  /// Whether "install unknown apps" is already allowed.
  bool canInstall = true;

  /// Whether asking for that permission manages to open the system screen.
  bool permissionScreenOpens = true;

  /// What the installer answers for an APK.
  String installAnswer = 'started';

  /// When set, the next install answers only once this completes.
  Completer<void>? holdNextInstall;

  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;

  @override
  Future<bool> requestPackageInstallsPermission() async => permissionScreenOpens;

  @override
  Future<String?> installApk(String filePath) async {
    installed.add(await File(filePath).readAsString());
    installedPaths.add(filePath);
    if (!installRequested.isCompleted) {
      installRequested.complete();
    }
    final hold = holdNextInstall;
    holdNextInstall = null;
    if (hold != null) {
      await hold.future;
    }
    return installAnswer;
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
