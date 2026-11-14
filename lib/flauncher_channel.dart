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

import 'package:flauncher/flauncher_channel_contract.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export 'package:flauncher/flauncher_channel_contract.dart';

/// The launcher's one way to the native side. One instance is created in
/// main.dart and provided to the widget tree by FLauncherApp.
///
/// Package and TV input events, the installed apps and the TV inputs arrive
/// decoded into the types of flauncher_channel_contract.dart; malformed ones
/// are logged and dropped here.
class FLauncherChannel {
  static const _methodChannel = MethodChannel(ChannelContract.methodChannel);
  static const _eventChannel = EventChannel(ChannelContract.eventChannel);
  static const _hdmiEventChannel = EventChannel(ChannelContract.hdmiEventChannel);
  static const _keyCaptureEventChannel = EventChannel(ChannelContract.keyCaptureEventChannel);
  static const _networkEventChannel = EventChannel(ChannelContract.networkEventChannel);

  /// The apps with a TV or phone launcher entry, icons and banners included.
  Future<List<InstalledApp>> getInstalledApps() async {
    final apps = await _methodChannel.invokeListMethod<dynamic>('getApplications');
    if (apps == null) {
      throw StateError('getApplications answered nothing');
    }
    return _decodeAll<InstalledApp>(apps, InstalledApp.decode, 'app');
  }

  Future<bool> applicationExists(String packageName) async =>
      await _methodChannel.invokeMethod('applicationExists', packageName);

  Future<void> launchApp(String packageName) async => await _methodChannel.invokeMethod('launchApp', packageName);

  Future<void> openSettings() async => await _methodChannel.invokeMethod('openSettings');

  Future<void> openWifiSettings() async => await _methodChannel.invokeMethod('openWifiSettings');

  /// Opens an Android editor using the installed keyboard; null means cancelled.
  Future<String?> showSystemTextInput({
    required String title,
    required String initialValue,
    required String fieldLabel,
    required String action,
    required String submitLabel,
    required bool allowEmpty,
    required Map<String, int> colors,
  }) async =>
      await _methodChannel.invokeMethod<String>('showSystemTextInput', {
        'title': title,
        'initialValue': initialValue,
        'fieldLabel': fieldLabel,
        'action': action,
        'submitLabel': submitLabel,
        'allowEmpty': allowEmpty,
        'colors': colors,
      });

  Future<void> openAppInfo(String packageName) async => await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async => await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async => await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<void> startAmbientMode() async => await _methodChannel.invokeMethod("startAmbientMode");

  /// Opens the system's power menu or shutdown confirmation.
  /// True means the request was accepted, not that the device powered off.
  Future<bool> shutdownDevice() async =>
      (await _methodChannel.invokeMethod<bool>('shutdownDevice')) ?? false;

  /// Turns off the screen without shutting down Android.
  Future<bool> standbyDevice() async =>
      (await _methodChannel.invokeMethod<bool>('standbyDevice')) ?? false;

  /// Calls [listener] with each package change the system reports.
  void addPackageEventListener(void Function(PackageEvent event) listener) =>
      _decoded<PackageEvent>(_eventChannel.receiveBroadcastStream(), PackageEvent.decode).listen(listener);

  /// Inputs added, removed, updated or changing state.
  Stream<TvInputEvent> get tvInputEvents => _decoded<TvInputEvent>(_hdmiEventChannel.receiveBroadcastStream(), TvInputEvent.decode);

  Future<List<dynamic>> getHdmiInputs() async {
    final result = await _methodChannel.invokeMethod('getHdmiInputs');
    return List<dynamic>.from(result ?? []);
  }

  /// Every input to show on the Inputs page, HDMI ones first.
  Future<List<TvInputEntry>> getTvInputs() async =>
      _decodeAll<TvInputEntry>(await _methodChannel.invokeMethod<Object?>('getTvInputs'), TvInputEntry.decode, 'TV input');

  Future<bool> launchTvInput(String inputId) async {
    final result = await _methodChannel.invokeMethod('launchTvInput', {'inputId': inputId});
    return result ?? false;
  }

  /// Opens the TV maker's `design` or `factory` engineering menu; false when
  /// this device does not have it.
  Future<bool> openEngineeringMenu(String menu) async =>
      (await _methodChannel.invokeMethod<bool>('openEngineeringMenu', {'menu': menu})) ?? false;

  Future<String?> installApk(String filePath) async => await _methodChannel.invokeMethod('installApk', filePath);

  Future<bool> canRequestPackageInstalls() async =>
      (await _methodChannel.invokeMethod('canRequestPackageInstalls')) ?? true;

  Future<bool> requestPackageInstallsPermission() async =>
      (await _methodChannel.invokeMethod('requestPackageInstallsPermission')) ?? false;

  Future<bool> requestStoragePermission() async =>
      (await _methodChannel.invokeMethod('requestStoragePermission')) ?? false;

  Future<bool> hasAllFilesAccess() async => (await _methodChannel.invokeMethod('hasAllFilesAccess')) ?? false;

  Future<bool> requestAllFilesAccess() async => (await _methodChannel.invokeMethod('requestAllFilesAccess')) ?? false;

  Future<String?> saveBackupToDownloads(String path) async =>
      await _methodChannel.invokeMethod<String>('saveBackupToDownloads', path);

  Future<List<dynamic>> listBackupJsonInDownloads() async =>
      (await _methodChannel.invokeListMethod('listBackupJsonInDownloads')) ?? <dynamic>[];

  Future<String?> readContentUri(String uri) async => await _methodChannel.invokeMethod<String>('readContentUri', uri);

  Future<String?> pickBackupJson() async => await _methodChannel.invokeMethod<String>('pickBackupJson');

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

  /// Emits each time the device gets a network, and again once that network
  /// is known to reach the internet.
  Stream<dynamic> get networkAvailableStream => _networkEventChannel.receiveBroadcastStream();

  /// [events] decoded; the ones [decode] rejects are left out.
  static Stream<T> _decoded<T>(Stream<dynamic> events, T? Function(Object? raw) decode) =>
      events.map<T?>(decode).where((event) => event != null).cast<T>();

  /// The entries of [raw] that [decode] accepts; nothing when [raw] is no list.
  static List<T> _decodeAll<T>(Object? raw, T? Function(Object? raw) decode, String what) {
    final decoded = <T>[];
    if (raw is! List) {
      return decoded;
    }
    for (final entry in raw) {
      final value = decode(entry);
      if (value == null) {
        debugPrint('FLauncherChannel: dropped a malformed $what');
      } else {
        decoded.add(value);
      }
    }
    return decoded;
  }
}
