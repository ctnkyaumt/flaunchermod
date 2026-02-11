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

import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flauncher_app.dart';

Future<void> main() async {
  // Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();
  Paint.enableDithering = true;
  
  debugPrint("FLauncher: Starting initialization");
  
  // Start the app without Firebase
  runZonedGuarded<void>(() async {
    try {
      debugPrint("FLauncher: Loading preferences");
      final sharedPreferences = await SharedPreferences.getInstance();
      
      debugPrint("FLauncher: Creating services");
      final imagePicker = ImagePicker();
      final fLauncherChannel = FLauncherChannel();
      
      debugPrint("FLauncher: Initializing database");
      final fLauncherDatabase = FLauncherDatabase(connect());
      
      debugPrint("FLauncher: Starting app");
      runApp(
        FLauncherApp(
          sharedPreferences,
          null, // crashlytics
          null, // analytics
          imagePicker,
          fLauncherChannel,
          fLauncherDatabase,
          null, // unsplash service
          null, // remote config
        ),
      );
      
      debugPrint("FLauncher: App started successfully!");
    } catch (e, stack) {
      debugPrint("FLauncher: Error during startup: $e");
      debugPrint(stack.toString());
    }
  }, (error, stack) {
    debugPrint("FLauncher: Uncaught error: $error");
    debugPrint(stack.toString());
  });
}
