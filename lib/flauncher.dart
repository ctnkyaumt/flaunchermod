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

import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/time_widget.dart';
import 'package:flauncher/widgets/hdmi_inputs_section.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FLauncher extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    debugPrint("FLauncher: Building main UI widget");
    return FocusTraversalGroup(
      policy: RowByRowTraversalPolicy(),
      child: Stack(
        children: [
          Consumer<WallpaperService>(
            builder: (_, wallpaper, __) => _wallpaper(context, wallpaper.wallpaperBytes, wallpaper.gradient.gradient),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _appBar(context),
            body: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Consumer<AppsService>(
                builder: (context, appsService, _) => appsService.initialized
                    ? Column(
                        children: [
                          // Everything wrapped in a single scrollable area
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Existing categories
                                  _categories(appsService.categoriesWithApps),
                                  
                                  // HDMI Inputs section
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                                    child: Text(
                                      "Inputs", // Section Title
                                      style: Theme.of(context).textTheme.headlineSmall,
                                    ),
                                  ),
                                  const HdmiInputsSection(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : _emptyState(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categories(List<CategoryWithApps> categoriesWithApps) => Column(
        children: categoriesWithApps.map((categoryWithApps) {
          switch (categoryWithApps.category.type) {
            case CategoryType.row:
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CategoryRow(
                    key: Key(categoryWithApps.category.id.toString()),
                    category: categoryWithApps.category,
                    applications: categoryWithApps.applications),
              );
            case CategoryType.grid:
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: AppsGrid(
                    key: Key(categoryWithApps.category.id.toString()),
                    category: categoryWithApps.category,
                    applications: categoryWithApps.applications),
              );
          }
        }).toList(),
      );

  AppBar _appBar(BuildContext context) => AppBar(
        actions: [
          // Wi-Fi button
          IconButton(
            padding: EdgeInsets.all(2),
            constraints: BoxConstraints(),
            splashRadius: 20,
            icon: Icon(Icons.wifi, size: 32, color: Colors.black54),
            onPressed: () => context.read<AppsService>().openWifiSettings(),
          ),
          // Settings button
          Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 2.0,
                top: 18.0,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2, tileMode: TileMode.decal),
                  child: Icon(Icons.settings_outlined, size: 32, color: Colors.black54),
                ),
              ),
              IconButton(
                padding: EdgeInsets.all(2),
                constraints: BoxConstraints(),
                splashRadius: 20,
                icon: Icon(Icons.settings_outlined, size: 32),
                onPressed: () => showDialog(context: context, builder: (_) => SettingsPanel()),
              ),
            ],
          ),
          // Time display
          Padding(
            padding: EdgeInsets.only(left: 16, right: 32),
            child: Align(
              alignment: Alignment.center,
              child: Transform.scale(
                scale: 1.3,
                child: TimeWidget(),
              ),
            ),
          ),
        ],
      );

  Widget _wallpaper(BuildContext context, Uint8List? wallpaperImage, Gradient gradient) {
    debugPrint("FLauncher: Building wallpaper");
    return wallpaperImage != null
        ? Image.memory(
            wallpaperImage,
            key: Key("background"),
            fit: BoxFit.cover,
            height: window.physicalSize.height,
            width: window.physicalSize.width,
          )
        : Container(key: Key("background"), decoration: BoxDecoration(gradient: gradient));
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Loading...", style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
}
