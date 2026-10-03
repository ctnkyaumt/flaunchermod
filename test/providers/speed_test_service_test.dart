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
import 'dart:io';
import 'dart:typed_data';

import 'package:flauncher/providers/speed_test_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late SpeedTestService service;
  late StreamSubscription<HttpRequest> subscription;
  late Future<void> Function(HttpRequest) respond;
  final requestedDownload = <int>[];
  final requestedUpload = <int>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requestedDownload.clear();
    requestedUpload.clear();
    respond = (request) async {
      final bytes = int.parse(request.uri.queryParameters['bytes']!);
      if (request.method == 'POST') {
        var received = 0;
        await for (final chunk in request) {
          received += chunk.length;
        }
        expect(received, bytes);
        requestedUpload.add(bytes);
        request.response.write('OK');
      } else {
        if (bytes > 0) requestedDownload.add(bytes);
        request.response.contentLength = bytes;
        request.response.add(Uint8List(bytes));
      }
      await request.response.close();
    };
    subscription = server.listen((request) async {
      try {
        await respond(request);
      } on SocketException {
        // Cancellation intentionally closes the client's connection.
      } on HttpException {
        // A deliberately truncated test response can close early.
      }
    });
    service = SpeedTestService(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      phaseDuration: const Duration(milliseconds: 300),
      requestTimeout: const Duration(milliseconds: 200),
      downloadLimit: 128 * 1024,
      uploadLimit: 64 * 1024,
      downloadChunk: 32 * 1024,
      uploadChunk: 16 * 1024,
    );
  });

  tearDown(() async {
    service.dispose();
    await subscription.cancel();
    await server.close(force: true);
  });

  test('Measures actual traffic and finishes immediately at both byte caps', () async {
    final watch = Stopwatch()..start();
    await service.start();
    expect(service.phase, SpeedTestPhase.complete);
    expect(service.latencyMs, greaterThan(0));
    expect(service.downloadMbps, greaterThan(0));
    expect(service.uploadMbps, greaterThan(0));
    expect(requestedDownload.reduce((a, b) => a + b), 128 * 1024);
    expect(requestedUpload.reduce((a, b) => a + b), 64 * 1024);
    expect(service.sampleLimited, isTrue);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(service.isRunning, isFalse);
  });

  test('Rejects server errors instead of reporting bandwidth', () async {
    respond = (request) async {
      request.response.statusCode = 503;
      await request.response.close();
    };
    await service.start();
    expect(service.phase, SpeedTestPhase.failed);
    expect(service.downloadMbps, isNull);
    expect(service.isRunning, isFalse);
  });

  test('Times out stalled headers and permits retry', () async {
    final normal = respond;
    respond = (_) async {};
    await service.start().timeout(const Duration(seconds: 2));
    expect(service.phase, SpeedTestPhase.failed);
    expect(service.error, contains('timed out'));
    respond = normal;
    await service.start();
    expect(service.phase, SpeedTestPhase.complete);
  });

  test('Cancel settles immediately and old I/O cannot overwrite the next run', () async {
    final normal = respond;
    final entered = Completer<void>();
    respond = (_) async {
      if (!entered.isCompleted) entered.complete();
    };
    final previous = service.start();
    await entered.future;
    service.cancel();
    expect(service.isRunning, isFalse);
    expect(service.phase, SpeedTestPhase.cancelled);
    respond = normal;
    await service.start();
    final download = service.downloadMbps;
    await previous.timeout(const Duration(seconds: 2));
    expect(service.phase, SpeedTestPhase.complete);
    expect(service.downloadMbps, download);
  });

  test('Deadline stops a stalled download body without claiming success', () async {
    service.dispose();
    service = SpeedTestService(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      phaseDuration: const Duration(milliseconds: 100),
      requestTimeout: const Duration(seconds: 2),
      downloadChunk: 32 * 1024,
    );
    final normal = respond;
    respond = (request) async {
      if (request.uri.queryParameters['bytes'] == '0') return normal(request);
      request.response.contentLength = 32 * 1024;
      await request.response.flush();
    };
    await service.start().timeout(const Duration(seconds: 2));
    expect(service.phase, SpeedTestPhase.failed);
    expect(service.downloadMbps, isNull);
  });

  test('Rejects truncated or substituted download data', () async {
    final normal = respond;
    respond = (request) async {
      if (request.uri.queryParameters['bytes'] == '0') return normal(request);
      request.response.contentLength = 1;
      request.response.add([0]);
      await request.response.close();
    };
    await service.start();
    expect(service.phase, SpeedTestPhase.failed);
    expect(service.downloadMbps, isNull);
  });

  test('Unacknowledged upload writes cannot produce an upload result', () async {
    final normal = respond;
    respond = (request) async {
      if (request.method != 'POST') return normal(request);
      await request.drain<void>();
      // The body was received but the server never acknowledged the request.
    };
    await service.start().timeout(const Duration(seconds: 2));
    expect(service.phase, SpeedTestPhase.failed);
    expect(service.downloadMbps, greaterThan(0));
    expect(service.uploadMbps, isNull);
  });

  test('Repeated Start during a run launches only one set of measurements', () async {
    final first = service.start();
    await service.start();
    await first;
    expect(requestedDownload.reduce((a, b) => a + b), service.downloadLimit);
  });

  test('Latency has an absolute deadline even with a continuously trickling body', () async {
    final clients = <HttpResponse>[];
    final drip = Timer.periodic(const Duration(milliseconds: 20), (_) {
      for (final response in clients) {
        response.add([0]);
        response.flush().catchError((Object _) {});
      }
    });
    respond = (request) async {
      clients.add(request.response);
    };
    try {
      await service.start().timeout(const Duration(seconds: 2));
      expect(service.phase, SpeedTestPhase.failed);
      expect(service.error, contains('timed out'));
    } finally {
      drip.cancel();
    }
  });

  for (final target in [SpeedTestPhase.download, SpeedTestPhase.upload]) {
    test('Cancellation during $target stops the run and leaves no final result', () async {
      final normal = respond;
      final entered = Completer<void>();
      respond = (request) async {
        final matches = target == SpeedTestPhase.upload
            ? request.method == 'POST'
            : request.method == 'GET' && request.uri.queryParameters['bytes'] != '0';
        if (!matches) return normal(request);
        if (!entered.isCompleted) entered.complete();
      };
      final pending = service.start();
      await entered.future.timeout(const Duration(seconds: 2));
      service.cancel();
      await pending.timeout(const Duration(seconds: 2));
      expect(service.phase, SpeedTestPhase.cancelled);
      expect(service.isRunning, isFalse);
      if (target == SpeedTestPhase.download) expect(service.downloadMbps, isNull);
      expect(service.uploadMbps, isNull);
    });
  }
}
