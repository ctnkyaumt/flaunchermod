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

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/unsplash_service.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService extends ChangeNotifier {
  final ImagePicker _imagePicker;
  final FLauncherChannel _fLauncherChannel;
  final UnsplashService? _unsplashService;
  late SettingsService _settingsService;

  late final File _wallpaperFile;
  late final Future<void> _ready;
  Object? _initializationError;
  Uint8List? _wallpaper;

  Uint8List? get wallpaperBytes => _wallpaper;

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
        (gradient) => gradient.uuid == _settingsService.gradientUuid,
        orElse: () => FLauncherGradients.charcoalDepths,
      );

  set settingsService(SettingsService settingsService) => _settingsService = settingsService;

  WallpaperService(this._imagePicker, this._fLauncherChannel, this._unsplashService) {
    debugPrint("WallpaperService: Initializing");
    _ready = _init();
  }

  Future<void> _init() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _wallpaperFile = File("${directory.path}/wallpaper");
      if (await _wallpaperFile.exists()) {
        debugPrint("WallpaperService: Found existing wallpaper");
        _wallpaper = await _wallpaperFile.readAsBytes();
      } else {
        debugPrint("WallpaperService: No existing wallpaper");
      }
      notifyListeners();
    } catch (e) {
      _initializationError = e;
      debugPrint("WallpaperService: Error initializing - $e");
    }
  }

  Future<void> pickWallpaper() async {
    await _ready;
    if (!await _fLauncherChannel.checkForGetContentAvailability()) {
      throw NoFileExplorerException();
    }
    final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      await _wallpaperFile.writeAsBytes(bytes);
      _wallpaper = bytes;
      await _settingsService.setUnsplashAuthor(null);
      notifyListeners();
    }
  }

  Future<void> randomFromUnsplash(String query) async {
    await _ready;
    if (_unsplashService == null) {
      debugPrint("WallpaperService: UnsplashService not available");
      return;
    }
    
    final photo = await _unsplashService!.randomPhoto(query);
    final bytes = await _unsplashService!.downloadPhoto(photo);
    await _wallpaperFile.writeAsBytes(bytes);
    _wallpaper = bytes;
    await _settingsService
        .setUnsplashAuthor(jsonEncode({"username": photo.username, "link": photo.userLink.toString()}));
    notifyListeners();
  }

  Future<List<Photo>> searchFromUnsplash(String query) {
    if (_unsplashService == null) {
      debugPrint("WallpaperService: UnsplashService not available");
      return Future.value([]);
    }
    return _unsplashService!.searchPhotos(query);
  }

  void onSettingsChanged() {
    notifyListeners();
  }

  Future<void> setFromUnsplash(Photo photo) async {
    await _ready;
    if (_unsplashService == null) {
      debugPrint("WallpaperService: UnsplashService not available");
      return;
    }
    
    final bytes = await _unsplashService!.downloadPhoto(photo);
    await _wallpaperFile.writeAsBytes(bytes);
    _wallpaper = bytes;
    await _settingsService
        .setUnsplashAuthor(jsonEncode({"username": photo.username, "link": photo.userLink.toString()}));
    notifyListeners();
  }

  Future<void> setGradient(FLauncherGradient fLauncherGradient) async {
    await _ready;
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }
    _wallpaper = null;
    await _settingsService.setUnsplashAuthor(null);
    await _settingsService.setGradientUuid(fLauncherGradient.uuid);
    notifyListeners();
  }

  Future<Uint8List?> exportWallpaper() async {
    await _ready;
    if (_initializationError != null) throw StateError("Unable to load wallpaper: $_initializationError");
    return _wallpaper;
  }

  Future<void> restoreWallpaper(Uint8List? bytes) async {
    await _ready;
    if (_initializationError != null) throw StateError("Unable to load wallpaper: $_initializationError");
    if (bytes == null) {
      if (await _wallpaperFile.exists()) await _wallpaperFile.delete();
    } else {
      final temporary = File("${_wallpaperFile.path}.restore");
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(_wallpaperFile.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    _wallpaper = bytes;
    notifyListeners();
  }
}

class NoFileExplorerException implements Exception {}
