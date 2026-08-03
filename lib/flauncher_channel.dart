/*
 * FLaunchermod
 * Copyright (C)
 * 2026 - ctnkyaumt
 * Forked from: 2021  Étienne Fesser
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

import 'package:flutter/services.dart';

class FLauncherChannel {
  static const _methodChannel = MethodChannel('me.efesser.flauncher/method');
  static const _eventChannel = EventChannel('me.efesser.flauncher/event');
  static const _hdmiEventChannel = EventChannel('me.efesser.flauncher/hdmi_event');
  static const _keyCaptureEventChannel = EventChannel('me.efesser.flauncher/key_capture_event');

  Future<List<dynamic>> getApplications() async => (await _methodChannel.invokeListMethod('getApplications'))!;

  Future<bool> applicationExists(String packageName) async =>
      await _methodChannel.invokeMethod('applicationExists', packageName);

  Future<void> launchApp(String packageName) async => await _methodChannel.invokeMethod('launchApp', packageName);

  Future<void> openSettings() async => await _methodChannel.invokeMethod('openSettings');

  Future<void> openWifiSettings() async => await _methodChannel.invokeMethod('openWifiSettings');

  Future<void> openAppInfo(String packageName) async => await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async => await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async => await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<void> startAmbientMode() async => await _methodChannel.invokeMethod("startAmbientMode");

  /// Shutdown the device
  /// 
  /// This method attempts to properly shutdown the device using various methods
  /// including MediaTek specific APIs when available
  Future<bool> shutdownDevice() async => await _methodChannel.invokeMethod("shutdownDevice");

  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) =>
      _eventChannel.receiveBroadcastStream().listen((event) => listener(event));

  Stream<dynamic> get appStream => _eventChannel.receiveBroadcastStream();
  Stream<dynamic> get hdmiInputStream => _hdmiEventChannel.receiveBroadcastStream();

  Future<List<dynamic>> getHdmiInputs() async {
    final result = await _methodChannel.invokeMethod('getHdmiInputs');
    return List<dynamic>.from(result ?? []);
  }

  Future<bool> launchTvInput(String inputId) async {
    final result = await _methodChannel.invokeMethod('launchTvInput', {'inputId': inputId});
    return result ?? false;
  }

  Future<String?> installApk(String filePath) async => await _methodChannel.invokeMethod('installApk', filePath);

  Future<bool> canRequestPackageInstalls() async =>
      (await _methodChannel.invokeMethod('canRequestPackageInstalls')) ?? true;

  Future<bool> requestPackageInstallsPermission() async =>
      (await _methodChannel.invokeMethod('requestPackageInstallsPermission')) ?? false;

  Future<bool> requestStoragePermission() async =>
      (await _methodChannel.invokeMethod('requestStoragePermission')) ?? false;

  Future<bool> hasAllFilesAccess() async => (await _methodChannel.invokeMethod('hasAllFilesAccess')) ?? false;

  Future<bool> requestAllFilesAccess() async => (await _methodChannel.invokeMethod('requestAllFilesAccess')) ?? false;

  Future<List<dynamic>> listBackupJsonInDownloads() async =>
      (await _methodChannel.invokeListMethod('listBackupJsonInDownloads')) ?? <dynamic>[];

  Future<String?> readContentUri(String uri) async => await _methodChannel.invokeMethod<String>('readContentUri', uri);

  Future<String?> pickBackupJson() async => await _methodChannel.invokeMethod<String>('pickBackupJson');

  Future<bool> shareFile(String path) async =>
      (await _methodChannel.invokeMethod('shareFile', path)) ?? false;

  /// Whether the accessibility service that intercepts remote buttons is on.
  Future<bool> isButtonMapperEnabled() async =>
      (await _methodChannel.invokeMethod('isButtonMapperEnabled')) ?? false;

  Future<bool> openAccessibilitySettings() async =>
      (await _methodChannel.invokeMethod('openAccessibilitySettings')) ?? false;

  /// Everything that can be a button mapping target, disabled apps included.
  Future<List<dynamic>> getMappableApplications() async =>
      (await _methodChannel.invokeListMethod('getMappableApplications')) ?? [];

  /// One of `UNAVAILABLE`, `PERMISSION_REQUIRED`, `READY`.
  Future<String> shizukuStatus() async =>
      (await _methodChannel.invokeMethod('shizukuStatus')) ?? "UNAVAILABLE";

  /// True when permission was already held; otherwise Shizuku shows its dialog
  /// and the answer arrives later.
  Future<bool> requestShizukuPermission() async =>
      (await _methodChannel.invokeMethod('requestShizukuPermission')) ?? false;

  /// The /dev/input nodes the helper managed to open.
  Future<List<dynamic>> shizukuInputDevices() async =>
      (await _methodChannel.invokeListMethod('shizukuInputDevices')) ?? [];

  /// Both routes to shell privilege at once: Shizuku state and ADB state.
  Future<Map<dynamic, dynamic>> rawInputStatus() async =>
      (await _methodChannel.invokeMapMethod('rawInputStatus')) ?? {};

  /// Pairs with the device's own adbd. Android 11+, where wireless debugging
  /// shows a pairing code and the port to use.
  Future<bool> adbPair(int port, String code) async =>
      (await _methodChannel.invokeMethod('adbPair', {"port": port, "code": code})) ?? false;

  /// Asks the accessibility service to (re)connect whichever route is available.
  Future<void> startRawInput() async => await _methodChannel.invokeMethod('startRawInput');

  /// Asks the running service to re-read the mapping table.
  Future<void> notifyButtonMappingsChanged() async =>
      await _methodChannel.invokeMethod('notifyButtonMappingsChanged');

  /// While capture mode is on, the service swallows every button and reports
  /// its key code on [keyCaptureStream] instead of acting on it.
  Future<void> setKeyCaptureMode(bool enabled) async =>
      await _methodChannel.invokeMethod('setKeyCaptureMode', enabled);

  Stream<dynamic> get keyCaptureStream => _keyCaptureEventChannel.receiveBroadcastStream();
}
