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

import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart';
import 'package:flauncher/stubs/unsplash_stubs.dart' as unsplash;

class UnsplashService {
  final unsplash.UnsplashClient _unsplashClient;

  UnsplashService(this._unsplashClient);

  Future<Photo> randomPhoto(String query) async {
    try {
      final photo = await _unsplashClient.photos
          .random(query: query, orientation: unsplash.PhotoOrientation.landscape)
          .goAndGet();
      return _buildPhoto(photo);
    } catch (e) {
      return Photo('dummy', 'No Unsplash Available', 
         Uri.parse('https://example.com'), 
         Uri.parse('https://example.com'),
         Uri.parse('https://example.com'));
    }
  }

  Future<List<Photo>> searchPhotos(String query) async {
    try {
      final photos = await _unsplashClient.photos
          .random(query: query, orientation: unsplash.PhotoOrientation.landscape, count: 30)
          .goAndGet();
      
      return [_buildPhoto(photos)];
    } catch (e) {
      return []; 
    }
  }

  Future<Uint8List> downloadPhoto(Photo photo) {
    return Future.value(Uint8List.fromList([0, 0, 0, 0]));
  }

  Future<Uint8List> _downloadResized(Photo photo) async {
    try {
      final size = window.physicalSize;
      return Uint8List.fromList([0, 0, 0, 0]);
    } catch (e) {
      return Uint8List.fromList([0, 0, 0, 0]);
    }
  }

  Photo _buildPhoto(unsplash.Photo photo) => Photo(
      photo.id, 
      photo.user.name, 
      Uri.parse(photo.urls.small), 
      photo.urls.raw,
      Uri.parse('https://example.com'));
}

class Photo {
  final String id;
  final String username;
  final Uri small;
  final Uri raw;
  final Uri userLink;

  Photo(this.id, this.username, this.small, this.raw, this.userLink);
}
