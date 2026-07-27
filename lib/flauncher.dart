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
import 'dart:ui';

import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/providers/app_install_service.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/category_row.dart';
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

  /// Shows a confirmation dialog before shutting down the device.
  Future<void> _showShutdownDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Shutdown Device'),
        content: Text('Are you sure you want to shutdown the device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('SHUTDOWN'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final channel = context.read<AppsService>().fLauncherChannel;
    final navigator = Navigator.of(context);
    var progressDismissed = false;
    void dismissProgress() {
      if (progressDismissed) {
        return;
      }
      progressDismissed = true;
      navigator.pop();
    }

    // The platform call can hang on devices that ignore the shutdown intent, so
    // give up after 10s and offer the force path instead of spinning forever.
    final timeout = Timer(Duration(seconds: 10), () {
      if (!mounted) {
        return;
      }
      dismissProgress();
      _showForceShutdownDialog(context);
    });

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _progressDialog(
        title: 'Shutting Down',
        message: 'Attempting to shutdown the device...',
        hint: 'Please wait',
      ),
    ));

    try {
      final succeeded = await channel.shutdownDevice();
      timeout.cancel();
      // On success the device is on its way down; leave the dialog up.
      if (succeeded || !mounted) {
        return;
      }
      dismissProgress();
      _showForceShutdownDialog(context);
    } catch (e) {
      timeout.cancel();
      if (!mounted) {
        return;
      }
      dismissProgress();
      _showShutdownErrorDialog(context, 'Failed to shutdown: ${e.toString()}');
    }
  }

  /// Shows a dialog offering force shutdown options when normal shutdown fails
  void _showForceShutdownDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Shutdown Failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The device did not respond to normal shutdown commands.'),
            SizedBox(height: 16),
            Text('Would you like to try force shutdown? This may cause data loss but is more likely to work.'),
          ],
        ),
        actions: _forceShutdownActions(dialogContext),
      ),
    );
  }

  void _showShutdownErrorDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            SizedBox(height: 16),
            Text('Would you like to try force shutdown?'),
          ],
        ),
        actions: _forceShutdownActions(dialogContext),
      ),
    );
  }

  List<Widget> _forceShutdownActions(BuildContext dialogContext) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('CANCEL'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            _attemptForceShutdown(context);
          },
          child: Text('FORCE SHUTDOWN'),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
        ),
      ];

  /// Attempts more aggressive force shutdown methods.
  ///
  /// This calls the same platform method; the native side escalates on retry.
  Future<void> _attemptForceShutdown(BuildContext context) async {
    final channel = context.read<AppsService>().fLauncherChannel;
    final navigator = Navigator.of(context);

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _progressDialog(
        message: 'Attempting force shutdown...',
        hint: 'This may take a few moments',
      ),
    ));

    String? error;
    try {
      await channel.shutdownDevice();
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) {
      return;
    }
    navigator.pop(); // close the progress dialog

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(error == null ? 'Force Shutdown Failed' : 'Error'),
        content: Text(error == null
            ? 'Unable to force shutdown the device. You may need to manually power off the device using the physical power button.'
            : 'An error occurred during force shutdown: $error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _progressDialog({String? title, required String message, required String hint}) => AlertDialog(
        title: title == null ? null : Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(message),
            SizedBox(height: 8),
            Text(hint, style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      );
}
