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
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

enum SpeedTestPhase { ready, latency, download, upload, complete, cancelled, failed }

/// A short HTTPS throughput estimate, using Cloudflare's documented test APIs.
/// No results telemetry, location lookup, background tests, or extra packages.
class SpeedTestService extends ChangeNotifier {
  final Uri endpoint;
  final Duration phaseDuration;
  final Duration requestTimeout;
  final Duration latencyDuration;
  final int downloadLimit;
  final int uploadLimit;
  final int downloadChunk;
  final int uploadChunk;

  SpeedTestService({
    Uri? endpoint,
    this.phaseDuration = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 8),
    this.latencyDuration = const Duration(seconds: 12),
    this.downloadLimit = 128 * 1024 * 1024,
    this.uploadLimit = 64 * 1024 * 1024,
    this.downloadChunk = 16 * 1024 * 1024,
    this.uploadChunk = 256 * 1024,
  }) : endpoint = endpoint ?? Uri.https('speed.cloudflare.com', '/');

  SpeedTestPhase phase = SpeedTestPhase.ready;
  double? latencyMs;
  double? downloadMbps;
  double? uploadMbps;
  double liveMbps = 0;
  double progress = 0;
  String? error;
  bool sampleLimited = false;
  _SpeedTestRun? _run;
  bool _disposed = false;

  bool get isRunning => _run != null;

  Future<void> start() async {
    if (_disposed || isRunning) return;
    final run = _SpeedTestRun();
    _run = run;
    latencyMs = downloadMbps = uploadMbps = null;
    liveMbps = progress = 0;
    error = null;
    sampleLimited = false;
    phase = SpeedTestPhase.latency;
    notifyListeners();
    Timer? latencyDeadline;
    var latencyExpired = false;
    try {
      final client = _client(run);
      latencyDeadline = Timer(latencyDuration, () {
        latencyExpired = true;
        client.close(force: true);
      });
      final samples = <double>[];
      for (var i = 0; i < 6; i++) {
        _check(run);
        final watch = Stopwatch()..start();
        final request = await client.getUrl(_uri('__down', 0)).timeout(requestTimeout);
        _headers(request);
        final response = await request.close().timeout(requestTimeout);
        watch.stop();
        _status(response);
        await _drain(response);
        if (i > 0) samples.add(watch.elapsedMicroseconds / 1000);
      }
      _check(run);
      samples.sort();
      latencyMs = samples[samples.length ~/ 2];
      latencyDeadline.cancel();
      _close(run, client);

      phase = SpeedTestPhase.download;
      progress = liveMbps = 0;
      notifyListeners();
      final download = await _transfer(run, upload: false);
      _check(run);
      downloadMbps = download;
      phase = SpeedTestPhase.upload;
      progress = liveMbps = 0;
      notifyListeners();
      final upload = await _transfer(run, upload: true);
      _check(run);
      uploadMbps = upload;
      phase = SpeedTestPhase.complete;
      progress = 1;
      liveMbps = 0;
    } on _Cancelled {
      // Cancellation already updates the UI and invalidates this run.
    } catch (e) {
      if (_current(run)) {
        phase = SpeedTestPhase.failed;
        liveMbps = 0;
        error = e is TimeoutException || latencyExpired
            ? 'Server timed out. Check your connection and retry.'
            : 'Test could not finish. Check your connection and retry.';
      }
    } finally {
      latencyDeadline?.cancel();
      run.close();
      if (_current(run)) {
        _run = null;
        notifyListeners();
      }
    }
  }

  Future<double> _transfer(_SpeedTestRun run, {required bool upload}) async {
    final client = _client(run);
    final watch = Stopwatch()..start();
    final limit = upload ? uploadLimit : downloadLimit;
    var reserved = 0;
    var bytes = 0;
    var acknowledgedMicros = 0;
    var expired = false;
    var chunkSize = upload ? uploadChunk : downloadChunk;
    final payload = upload ? Uint8List(2 * 1024 * 1024) : null;
    final deadline = Timer(phaseDuration, () {
      expired = true;
      client.close(force: true);
    });
    final ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!_current(run)) return;
      liveMbps = _mbps(bytes, upload ? acknowledgedMicros : watch.elapsedMicroseconds);
      progress = (watch.elapsedMicroseconds / phaseDuration.inMicroseconds).clamp(0.0, 1.0).toDouble();
      notifyListeners();
    });

    Future<void> worker() async {
      while (!expired && _current(run) && reserved < limit) {
        final size = (limit - reserved).clamp(0, chunkSize).toInt();
        reserved += size; // Reserve before awaiting so parallel downloads stay within the cap.
        final requestWatch = Stopwatch()..start();
        try {
          final request = await (upload
                  ? client.postUrl(_uri('__up', size))
                  : client.getUrl(_uri('__down', size)))
              .timeout(requestTimeout);
          _check(run);
          _headers(request);
          if (upload) {
            request.headers.contentType = ContentType.binary;
            request.contentLength = size;
            await request.addStream(Stream.value(Uint8List.sublistView(payload!, 0, size)))
                .timeout(requestTimeout);
          }
          final response = await request.close().timeout(requestTimeout);
          _status(response);
          if (upload) {
            await _drain(response);
            if (expired) break;
            _check(run);
            bytes += size; // Only server-acknowledged POSTs contribute to upload speed.
            acknowledgedMicros = watch.elapsedMicroseconds;
            if (requestWatch.elapsedMilliseconds < 750 && chunkSize < payload!.length) {
              chunkSize = (chunkSize * 2).clamp(0, payload.length).toInt();
            }
          } else {
            final encoding = response.headers.value(HttpHeaders.contentEncodingHeader);
            if ((encoding != null && encoding != 'identity') ||
                (response.contentLength >= 0 && response.contentLength != size)) {
              throw const HttpException('Unexpected download payload');
            }
            var received = 0;
            await for (final data in response.timeout(requestTimeout)) {
              _check(run);
              if (expired) break;
              received += data.length;
              if (received > size) throw const HttpException('Oversized download');
              bytes += data.length;
            }
            if (!expired && received != size) throw const HttpException('Truncated download');
          }
        } catch (_) {
          if (!expired) rethrow;
        }
      }
    }

    try {
      await Future.wait([worker(), if (!upload) worker()]);
      _check(run);
      watch.stop();
      if (bytes == 0) throw TimeoutException('No measurement received');
      if (!expired && reserved >= limit) sampleLimited = true;
      return _mbps(bytes, upload ? acknowledgedMicros : watch.elapsedMicroseconds);
    } finally {
      deadline.cancel();
      ticker.cancel();
      _close(run, client);
    }
  }

  static double _mbps(int bytes, int microseconds) => microseconds <= 0 ? 0 : bytes * 8 / microseconds;

  Uri _uri(String path, int bytes) => endpoint.resolve(path).replace(queryParameters: {
        'bytes': '$bytes',
        'cacheBust': '${DateTime.now().microsecondsSinceEpoch}',
      });

  HttpClient _client(_SpeedTestRun run) {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = requestTimeout
      ..maxConnectionsPerHost = 2
      ..userAgent = 'FLaunchermod/0.0.6';
    run.clients.add(client);
    return client;
  }

  void _headers(HttpClientRequest request) {
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
  }

  void _status(HttpClientResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Test server returned ${response.statusCode}');
    }
  }

  Future<void> _drain(HttpClientResponse response) => _readSmallResponse(response).timeout(requestTimeout);

  Future<void> _readSmallResponse(HttpClientResponse response) async {
    var bytes = 0;
    await for (final data in response.timeout(requestTimeout)) {
      bytes += data.length;
      if (bytes > 64 * 1024) throw const HttpException('Unexpected server response');
    }
  }

  bool _current(_SpeedTestRun run) => !_disposed && identical(_run, run);
  void _check(_SpeedTestRun run) {
    if (!_current(run)) throw _Cancelled();
  }

  void _close(_SpeedTestRun run, HttpClient client) {
    client.close(force: true);
    run.clients.remove(client);
  }

  void cancel() {
    final run = _run;
    if (run == null) return;
    _run = null; // A new run can start immediately; old callbacks cannot change its state.
    run.close();
    phase = SpeedTestPhase.cancelled;
    liveMbps = 0;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

class _SpeedTestRun {
  final clients = <HttpClient>{};
  void close() {
    for (final client in clients) {
      client.close(force: true);
    }
    clients.clear();
  }
}

class _Cancelled implements Exception {}
