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

import 'dart:ui';

import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/device_power_dialog.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/hdmi_inputs_section.dart';
import 'package:flauncher/widgets/weather_widget.dart';
import 'package:flauncher/widgets/settings/install_apps_panel_page.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/time_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Vertical slack within which two focus nodes count as being on the same row.
const double _rowTolerance = 50;

class FLauncher extends StatefulWidget {
  @override
  _FLauncherState createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> with WidgetsBindingObserver implements PageNavigationHandler {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _startupPermissionsFlowActive = false;
  bool _startupInstallPermissionPrompted = false;
  bool _startupAllFilesPrompted = false;
  bool _powerDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInstallFlow();
      _runStartupPermissionsFlow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInstallFlow();
      _runStartupPermissionsFlow();
    }
  }

  void _checkInstallFlow() {
    final installService = context.read<AppInstallService>();
    if (installService.isInstallingFlow) {
      installService.setInstallingFlow(false);
      showDialog(
        context: context,
        builder: (_) => SettingsPanel(initialRoute: InstallAppsPanelPage.routeName),
      );
    }
  }

  Future<void> _runStartupPermissionsFlow() async {
    if (_startupPermissionsFlowActive) return;
    _startupPermissionsFlowActive = true;

    try {
      final settings = context.read<SettingsService>();
      if (settings.startupPermissionsCompleted) return;

      final channel = context.read<AppsService>().fLauncherChannel;

      final canInstall = await channel.canRequestPackageInstalls();
      if (!canInstall) {
        if (!_startupInstallPermissionPrompted) {
          _startupInstallPermissionPrompted = true;
          await channel.requestPackageInstallsPermission();
        }
        return;
      }

      final hasAllFiles = await channel.hasAllFilesAccess();
      if (!hasAllFiles) {
        if (_startupAllFilesPrompted) return;
        _startupAllFilesPrompted = true;
        if (!mounted) return;
        final openButtonFocus = FocusNode();
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            Future<void> openAllFilesSettings() async {
              final opened = await channel.requestAllFilesAccess();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              if (!opened && mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text("Unable to open storage permission settings")),
                );
              }
            }

            return FocusTraversalGroup(
              child: FocusScope(
                autofocus: true,
                child: FocusKeyboardListener(
                  onPressed: (key) {
                    if (key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.gameButtonA) {
                      openAllFilesSettings();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  builder: (context) => Builder(
                    builder: (dialogContext) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await Future.delayed(Duration(milliseconds: 100));
                        if (!openButtonFocus.canRequestFocus) return;
                        FocusScope.of(dialogContext).requestFocus(openButtonFocus);
                      });
                      return AlertDialog(
                        title: Text("Storage permission required"),
                        content: Text(
                          "This app requires full storage access to restore from a backup.",
                        ),
                        actions: [
                          OutlinedButton(
                            focusNode: openButtonFocus,
                            autofocus: true,
                            onPressed: openAllFilesSettings,
                            child: Text("Open"),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
        openButtonFocus.dispose();
        return;
      }

      await settings.setStartupPermissionsCompleted(true);
    } finally {
      _startupPermissionsFlowActive = false;
    }
  }

  void _navigateToPage(int page) {
    if (page >= 0 && page <= 1) {
      setState(() {
        _currentPage = page;
      });
      _pageController.animateToPage(
        page,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        // After page animation completes, focus on the first focusable element
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(Duration(milliseconds: 100), () {
            if (page == 1) {
              // Focus the first HDMI input on Inputs page
              _focusFirstContentNode();
            } else if (page == 0) {
              // Focus the first app card in the top category
              _focusFirstContentNode();
            }
          });
        });
      });
    }
  }

  void _focusFirstContentNode() {
    final scope = FocusManager.instance.primaryFocus?.nearestScope;
    if (scope != null) {
      // Get all focusable nodes and filter out app bar icons
      final allNodes = scope.traversalDescendants.where((node) => node.canRequestFocus).toList();

      if (allNodes.isEmpty) {
        return;
      }
      
      // Sort top-to-bottom, then left-to-right within a row. Nodes less than
      // _rowTolerance apart vertically count as the same row.
      allNodes.sort((a, b) {
        final dy = a.rect.center.dy - b.rect.center.dy;
        if (dy.abs() > _rowTolerance) return dy < 0 ? -1 : 1;
        return a.rect.center.dx.compareTo(b.rect.center.dx);
      });

      // Find the first node that isn't an app bar action.
      final contentNode = allNodes.firstWhere(
        (node) => node.rect.center.dy > appBarBottom,
        orElse: () => allNodes.first,
      );

      contentNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: PageAwareTraversalPolicy(this),
      child: Stack(
        children: [
          Positioned.fill(
            child: Consumer<WallpaperService>(
              builder: (_, wallpaper, __) => _wallpaper(context, wallpaper.wallpaperBytes, wallpaper.gradient.gradient),
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _appBar(context),
            body: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Consumer<AppsService>(
                    builder: (context, appsService, _) => appsService.initialized
                        ? PageView(
                            controller: _pageController,
                            scrollDirection: Axis.vertical,
                            physics: NeverScrollableScrollPhysics(), // Disable swipe, use keyboard only
                            onPageChanged: (page) {
                              setState(() {
                                _currentPage = page;
                              });
                            },
                            children: [
                              // Apps Page
                              _buildAppsPage(appsService.categoriesWithApps),
                              // Inputs Page
                              _buildInputsPage(),
                            ],
                          )
                        : _emptyState(context),
                  ),
                ),
                // Page indicator dots
                _buildPageIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool handlePageNavigation(TraversalDirection direction, FocusNode currentNode) {
    if (direction == TraversalDirection.down && _currentPage == 0) {
      _navigateToPage(1);
      return true;
    } else if (direction == TraversalDirection.up && _currentPage == 1) {
      _navigateToPage(0);
      return true;
    }
    return false;
  }

  Widget _buildAppsPage(List<CategoryWithApps> categoriesWithApps) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Apps" title
          Padding(
            padding: EdgeInsets.only(left: 16, bottom: 16),
            child: Text(
              "Apps",
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Categories
          _categories(categoriesWithApps),
        ],
      ),
    );
  }

  Widget _buildInputsPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Inputs" title
          Padding(
            padding: EdgeInsets.only(left: 16, bottom: 16),
            child: Text(
              "Inputs",
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // HDMI Inputs section
          const HdmiInputsSection(),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Positioned(
      right: 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(2, (index) {
            return Container(
              margin: EdgeInsets.symmetric(vertical: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index
                    ? Colors.white
                    : Colors.white.withOpacity(0.3),
              ),
            );
          }),
        ),
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
        title: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 60),
            child: WeatherWidget(),
          ),
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              padding: EdgeInsets.all(8),
              iconSize: 36,
              splashRadius: 24,
              icon: Icon(Icons.power_settings_new, color: Colors.white),
              onPressed: () => _showShutdownDialog(context),
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              padding: EdgeInsets.all(8),
              iconSize: 36,
              splashRadius: 24,
              icon: Icon(Icons.wifi, color: Colors.white),
              onPressed: () => context.read<AppsService>().openWifiSettings(),
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              padding: EdgeInsets.all(8),
              iconSize: 36,
              splashRadius: 24,
              icon: Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () => showDialog(context: context, builder: (_) => SettingsPanel()),
            ),
          ),
          Container(
            margin: EdgeInsets.only(left: 16, right: 32),
            alignment: Alignment.center,
            height: 56,
            child: Center(
              child: TimeWidget(),
            ),
          ),
        ],
      );

  // Sizing to the *physical* pixel count used to blow the image up to
  // devicePixelRatio times the screen size; filling the stack lets the engine
  // pick the right raster size instead.
  Widget _wallpaper(BuildContext context, Uint8List? wallpaperImage, Gradient gradient) => wallpaperImage != null
      ? Image.memory(
          wallpaperImage,
          key: Key("background"),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        )
      : Container(key: Key("background"), decoration: BoxDecoration(gradient: gradient));

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

  Future<void> _showShutdownDialog(BuildContext context) async {
    if (_powerDialogOpen) return;
    _powerDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DevicePowerDialog(channel: context.read<AppsService>().fLauncherChannel),
      );
    } finally {
      _powerDialogOpen = false;
    }
  }
}
