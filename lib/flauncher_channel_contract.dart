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

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Channel names and event keys shared with the native side, the Dart copy of
/// android/app/src/main/kotlin/me/efesser/flauncher/ChannelContract.kt.
/// Change both together.
class ChannelContract {
  ChannelContract._();

  static const methodChannel = 'me.efesser.flauncher/method';
  static const eventChannel = 'me.efesser.flauncher/event';
  static const hdmiEventChannel = 'me.efesser.flauncher/hdmi_event';
  static const keyCaptureEventChannel = 'me.efesser.flauncher/key_capture_event';
  static const networkEventChannel = 'me.efesser.flauncher/network_event';

  /// Every package and TV input event carries its kind under this key.
  static const keyAction = 'action';

  // Package events (eventChannel).
  static const actionPackageRemoved = 'PACKAGE_REMOVED';
  static const actionPackageAdded = 'PACKAGE_ADDED';
  static const actionPackageChanged = 'PACKAGE_CHANGED';
  static const actionPackagesAvailable = 'PACKAGES_AVAILABLE';
  static const keyPackageName = 'packageName';
  static const keyActivityInfo = 'activityInfo';
  static const keyActivitiesInfo = 'activitiesInfo';

  // TV input events (hdmiEventChannel).
  static const actionInputAdded = 'INPUT_ADDED';
  static const actionInputRemoved = 'INPUT_REMOVED';
  static const actionInputUpdated = 'INPUT_UPDATED';
  static const actionInputStateChanged = 'INPUT_STATE_CHANGED';
  static const keyInputInfo = 'inputInfo';
  static const keyInputId = 'inputId';
  static const keyState = 'state';

  // Key capture events (keyCaptureEventChannel), read as maps by
  // lib/providers/button_mapping/button_capture_session.dart.
  static const keyCaptureCancelled = 'captureCancelled';
  static const keyKeyCode = 'keyCode';
  static const keyScanCode = 'scanCode';
  static const keyKeyLabel = 'keyLabel';
  static const keyKeyAction = 'keyAction';
  static const keyDevice = 'device';
  static const keyRawCode = 'rawCode';
  static const keyRawScanCode = 'rawScanCode';

  // An app description (getApplications and package events), as built by
  // AppCatalog.kt; its package name is under keyPackageName.
  static const keyAppName = 'name';
  static const keyAppVersion = 'version';
  static const keyAppBanner = 'banner';
  static const keyAppIcon = 'icon';
  static const keyAppSideloaded = 'sideloaded';
  static const keyAppIsSystemApp = 'isSystemApp';

  // A TV input entry (getTvInputs and TV input events), as built by
  // TvInputs.entryMap in TvInputs.kt.
  static const keyInputEntryId = 'id';
  static const keyInputEntryName = 'name';
  static const keyInputEntryType = 'type';
  static const keyInputEntryGroup = 'group';
  static const inputGroupHdmi = 'hdmi';
}

/// An app the system reports as installed and launchable.
class InstalledApp {
  final String packageName;
  final String name;

  /// Null when the package declares no version name.
  final String? version;

  /// PNG bytes, or null when the app has none.
  final Uint8List? banner;
  final Uint8List? icon;

  /// True for apps that only have a phone/tablet launcher entry.
  final bool sideloaded;
  final bool isSystemApp;

  const InstalledApp({
    required this.packageName,
    required this.name,
    this.version,
    this.banner,
    this.icon,
    this.sideloaded = false,
    this.isSystemApp = false,
  });

  /// Null unless [raw] is an app description with a package name and a name.
  /// Optional fields of the wrong type count as absent.
  static InstalledApp? decode(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final packageName = raw[ChannelContract.keyPackageName];
    if (packageName is! String || packageName.isEmpty) {
      return null;
    }
    final name = raw[ChannelContract.keyAppName];
    if (name is! String) {
      return null;
    }
    final version = raw[ChannelContract.keyAppVersion];
    final banner = raw[ChannelContract.keyAppBanner];
    final icon = raw[ChannelContract.keyAppIcon];
    return InstalledApp(
      packageName: packageName,
      name: name,
      version: version is String ? version : null,
      banner: banner is Uint8List ? banner : null,
      icon: icon is Uint8List ? icon : null,
      sideloaded: raw[ChannelContract.keyAppSideloaded] == true,
      isSystemApp: raw[ChannelContract.keyAppIsSystemApp] == true,
    );
  }
}

enum PackageEventKind { added, changed, available, removed }

/// A change to the installed apps, as the system reports it.
class PackageEvent {
  final PackageEventKind kind;

  /// The apps reported: one for [PackageEventKind.added] and
  /// [PackageEventKind.changed], at least one for [PackageEventKind.available],
  /// none for [PackageEventKind.removed].
  final List<InstalledApp> apps;

  /// The package that is gone; set for [PackageEventKind.removed] only.
  final String? removedPackageName;

  const PackageEvent._(this.kind, this.apps, this.removedPackageName);

  PackageEvent.added(InstalledApp app) : this._(PackageEventKind.added, List.unmodifiable([app]), null);

  PackageEvent.changed(InstalledApp app) : this._(PackageEventKind.changed, List.unmodifiable([app]), null);

  PackageEvent.available(List<InstalledApp> apps)
      : this._(PackageEventKind.available, List.unmodifiable(apps), null);

  PackageEvent.removed(String packageName) : this._(PackageEventKind.removed, const [], packageName);

  /// The event the native side sent as [raw], or null (logged) when it is
  /// malformed. Invalid entries of an available batch are left out; a batch
  /// with none left is dropped.
  static PackageEvent? decode(Object? raw) {
    if (raw is! Map) {
      return _drop('not a map');
    }
    final action = raw[ChannelContract.keyAction];
    if (action == ChannelContract.actionPackageAdded || action == ChannelContract.actionPackageChanged) {
      final app = InstalledApp.decode(raw[ChannelContract.keyActivityInfo]);
      if (app == null) {
        return _drop('$action without a valid ${ChannelContract.keyActivityInfo}');
      }
      return action == ChannelContract.actionPackageAdded ? PackageEvent.added(app) : PackageEvent.changed(app);
    }
    if (action == ChannelContract.actionPackagesAvailable) {
      final reported = raw[ChannelContract.keyActivitiesInfo];
      if (reported is! List) {
        return _drop('$action without ${ChannelContract.keyActivitiesInfo}');
      }
      final apps = <InstalledApp>[];
      for (final entry in reported) {
        final app = InstalledApp.decode(entry);
        if (app == null) {
          debugPrint('FLauncherChannel: left an invalid app out of $action');
        } else {
          apps.add(app);
        }
      }
      if (apps.isEmpty) {
        return _drop('$action without a valid app');
      }
      return PackageEvent.available(apps);
    }
    if (action == ChannelContract.actionPackageRemoved) {
      final packageName = raw[ChannelContract.keyPackageName];
      if (packageName is! String || packageName.isEmpty) {
        return _drop('$action without ${ChannelContract.keyPackageName}');
      }
      return PackageEvent.removed(packageName);
    }
    return _drop('unknown action $action');
  }

  static PackageEvent? _drop(String reason) {
    debugPrint('FLauncherChannel: dropped a package event: $reason');
    return null;
  }
}

/// One input the Inputs page shows.
class TvInputEntry {
  final String id;
  final String name;

  /// Android's TvInputInfo type, e.g. 1007 for HDMI; null when not reported.
  final int? type;

  /// Shown in the HDMI row rather than the Other row.
  final bool isHdmi;

  const TvInputEntry({required this.id, required this.name, this.type, required this.isHdmi});

  /// Null unless [raw] is an input entry with an id. A missing name reads
  /// "Unknown Input"; a missing group counts as HDMI.
  static TvInputEntry? decode(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final id = raw[ChannelContract.keyInputEntryId];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final name = raw[ChannelContract.keyInputEntryName];
    final type = raw[ChannelContract.keyInputEntryType];
    final group = raw[ChannelContract.keyInputEntryGroup];
    return TvInputEntry(
      id: id,
      name: name is String ? name : 'Unknown Input',
      type: type is int ? type : null,
      isHdmi: (group is String ? group : ChannelContract.inputGroupHdmi) == ChannelContract.inputGroupHdmi,
    );
  }
}

enum TvInputEventKind { added, removed, updated, stateChanged }

/// A change to the TV inputs, as the system reports it.
class TvInputEvent {
  final TvInputEventKind kind;
  final String inputId;

  /// The input as it now is; set for [TvInputEventKind.added] and
  /// [TvInputEventKind.updated].
  final TvInputEntry? input;

  /// Android's input state; set for [TvInputEventKind.stateChanged].
  final int? state;

  const TvInputEvent._(this.kind, this.inputId, {this.input, this.state});

  /// The event the native side sent as [raw], or null (logged) when it is malformed.
  static TvInputEvent? decode(Object? raw) {
    if (raw is! Map) {
      return _drop('not a map');
    }
    final action = raw[ChannelContract.keyAction];
    if (action == ChannelContract.actionInputAdded || action == ChannelContract.actionInputUpdated) {
      final input = TvInputEntry.decode(raw[ChannelContract.keyInputInfo]);
      if (input == null) {
        return _drop('$action without a valid ${ChannelContract.keyInputInfo}');
      }
      final kind = action == ChannelContract.actionInputAdded ? TvInputEventKind.added : TvInputEventKind.updated;
      return TvInputEvent._(kind, input.id, input: input);
    }
    final inputId = raw[ChannelContract.keyInputId];
    if (action == ChannelContract.actionInputRemoved || action == ChannelContract.actionInputStateChanged) {
      if (inputId is! String || inputId.isEmpty) {
        return _drop('$action without ${ChannelContract.keyInputId}');
      }
      if (action == ChannelContract.actionInputRemoved) {
        return TvInputEvent._(TvInputEventKind.removed, inputId);
      }
      final state = raw[ChannelContract.keyState];
      if (state is! int) {
        return _drop('$action without ${ChannelContract.keyState}');
      }
      return TvInputEvent._(TvInputEventKind.stateChanged, inputId, state: state);
    }
    return _drop('unknown action $action');
  }

  static TvInputEvent? _drop(String reason) {
    debugPrint('FLauncherChannel: dropped a TV input event: $reason');
    return null;
  }
}
