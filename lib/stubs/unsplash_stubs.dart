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

// Stub classes for Unsplash client

class UnsplashClient {
  UnsplashClient({dynamic settings});
  
  PhotosApi get photos => PhotosApi();
}

class ClientSettings {
  ClientSettings({
    required bool debug, 
    required AppCredentials credentials
  });
}

class AppCredentials {
  AppCredentials({
    required String accessKey, 
    required String secretKey
  });
}

class PhotosApi {
  Future<Response> random({
    String? query, 
    dynamic orientation, 
    int? count
  }) async {
    return Response();
  }
  
  Future<Response> searchPhotos({
    required String query,
    dynamic orientation,
  }) async {
    return Response();
  }
}

class Response {
  Future<Photo> goAndGet() async {
    return Photo();
  }
  
  List<Photo> get results => [];
}

class Photo {
  String id = '';
  User user = User();
  Urls urls = Urls();
  Uri get userLink => Uri.parse('https://example.com');
}

class User {
  String name = '';
}

class Urls {
  String small = '';
  Uri raw = Uri.parse('https://example.com');
}

// Enums
class PhotoOrientation {
  static const landscape = PhotoOrientation();
}

class ResizeFitMode {
  static const clip = ResizeFitMode();
}

class ImageFormat {
  static const jpg = ImageFormat();
}

// Extensions
extension UriExtension on Uri {
  Uri resizePhoto({
    required int width,
    required int height,
    dynamic fit,
    dynamic format,
  }) {
    return this;
  }
}
