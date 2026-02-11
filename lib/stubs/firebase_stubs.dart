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

import 'package:flutter/widgets.dart';

// Stub classes to replace Firebase dependencies

class FirebaseCrashlytics {
  static final FirebaseCrashlytics instance = FirebaseCrashlytics();
  
  void setCrashlyticsCollectionEnabled(bool enabled) {
    // Do nothing
  }
  
  void recordError(dynamic exception, StackTrace? stack) {
    // Do nothing
  }
  
  void recordFlutterError(dynamic flutterError) {
    // Do nothing
  }
}

class FirebaseAnalytics {
  static final FirebaseAnalytics instance = FirebaseAnalytics();
  
  void setAnalyticsCollectionEnabled(bool enabled) {
    // Do nothing
  }
}

class FirebaseAnalyticsObserver extends NavigatorObserver {
  FirebaseAnalyticsObserver({required FirebaseAnalytics analytics}) {
    // Do nothing
  }
}

class FirebaseRemoteConfig {
  static final FirebaseRemoteConfig instance = FirebaseRemoteConfig();
  
  String getString(String key) {
    return ''; // Return empty string for all keys
  }
  
  bool getBool(String key) {
    return false; // Return false for all keys
  }
  
  Future<bool> fetchAndActivate() async {
    return false;
  }
}

class FirebaseApp {}

class RemoteConfigSettings {}

class RemoteConfigValue {}
