/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

  Future<bool> shareFile(String path) async =>
      (await _methodChannel.invokeMethod('shareFile', path)) ?? false;
}
