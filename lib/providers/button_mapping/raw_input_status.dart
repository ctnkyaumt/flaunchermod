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

/// Whether the shell-privileged helper that reads `/dev/input` can run.
enum ShizukuStatus { unavailable, permissionRequired, ready }

/// State of the launcher's own connection to the device's adbd.
enum AdbState { disconnected, connecting, connected, failed }

/// Both routes to the shell privilege that reading `/dev/input` needs.
class RawInputStatus {
  final ShizukuStatus shizuku;
  final bool shizukuConnected;
  final AdbState adb;

  /// Last ADB failure, worth showing because the causes are all user-fixable.
  final String? adbError;

  /// Whether wireless-debugging pairing is offered as a setup option.
  /// An authorised TCP connection can also work without pairing.
  final bool pairingRequired;

  const RawInputStatus({
    this.shizuku = ShizukuStatus.unavailable,
    this.shizukuConnected = false,
    this.adb = AdbState.disconnected,
    this.adbError,
    this.pairingRequired = false,
  });

  /// Whether firmware buttons can be read right now.
  bool get ready => shizukuConnected || adb == AdbState.connected;

  /// Whether anything a screen shows differs between the two statuses.
  bool differsFrom(RawInputStatus other) =>
      shizuku != other.shizuku ||
      shizukuConnected != other.shizukuConnected ||
      adb != other.adb ||
      adbError != other.adbError ||
      pairingRequired != other.pairingRequired;

  static RawInputStatus fromMap(Map<dynamic, dynamic> map) => RawInputStatus(
        shizuku: _shizuku(map["shizuku"] as String?),
        shizukuConnected: map["shizukuConnected"] as bool? ?? false,
        adb: _adb(map["adb"] as String?),
        adbError: map["adbError"] as String?,
        pairingRequired: map["pairingRequired"] as bool? ?? false,
      );

  static ShizukuStatus _shizuku(String? name) {
    switch (name) {
      case "READY":
        return ShizukuStatus.ready;
      case "PERMISSION_REQUIRED":
        return ShizukuStatus.permissionRequired;
      default:
        return ShizukuStatus.unavailable;
    }
  }

  static AdbState _adb(String? name) {
    switch (name) {
      case "CONNECTED":
        return AdbState.connected;
      case "CONNECTING":
        return AdbState.connecting;
      case "FAILED":
        return AdbState.failed;
      default:
        return AdbState.disconnected;
    }
  }
}
