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
import 'dart:io';
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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class FLauncher extends StatefulWidget {
  @override
  _FLauncherState createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _startupPermissionsFlowActive = false;
  bool _startupInstallPermissionPrompted = false;
  bool _startupAllFilesPrompted = false;
  final GlobalKey _screenshotBoundaryKey = GlobalKey();
  StreamSubscription<dynamic>? _nativeKeyEventsSub;
  final Map<String, int> _nativeKeyHandledAtMs = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInstallFlow();
      _runStartupPermissionsFlow();
      _startNativeKeyEventsListener();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeKeyEventsSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startNativeKeyEventsListener() {
    _nativeKeyEventsSub?.cancel();
    final channel = context.read<AppsService>().fLauncherChannel;
    _nativeKeyEventsSub = channel.keyEventStream.listen((event) {
      if (!mounted) return;
      if (event is! Map) return;
      final action = event['action'];
      if (action != 'up' && action != 'down') return;
      final keyCode = event['keyCode'];
      final scanCode = event['scanCode'];
      final repeatCount = event['repeatCount'];
      if (keyCode is! int || scanCode is! int) return;
      if (action == 'down' && repeatCount is int && repeatCount != 0) {
        return;
      }
      const handledByFlutter = {19, 20, 21, 22, 23, 66, 4};
      if (keyCode != 0 && handledByFlutter.contains(keyCode)) {
        return;
      }
      final keyId = keyCode != 0 ? 'kc:$keyCode' : 'sc:$scanCode';
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastHandled = _nativeKeyHandledAtMs[keyId];
      if (lastHandled != null && now - lastHandled < 500) {
        return;
      }
      final result = _handleGlobalRemoteBindingKeyData(context, keyCode: keyCode, scanCode: scanCode);
      if (result == KeyEventResult.handled || result == KeyEventResult.skipRemainingHandlers) {
        _nativeKeyHandledAtMs[keyId] = now;
      }
    });
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
      
      // Sort by Y position to get top-to-bottom order, then by X position
      allNodes.sort((a, b) {
        final dyDiff = a.rect.center.dy.compareTo(b.rect.center.dy);
        if (dyDiff.abs() > 50) return dyDiff; // Different rows
        return a.rect.center.dx.compareTo(b.rect.center.dx); // Same row, sort by X
      });
      
      // Find the first node that's not in the app bar (Y > 100)
      final contentNode = allNodes.firstWhere(
        (node) => node.rect.center.dy > 100,
        orElse: () => allNodes.first,
      );
      
      contentNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("FLauncher: Building main UI widget");
    return FocusKeyboardListener(
      onRawKey: (event) => _handleGlobalRemoteBinding(context, event),
      onPressed: (key) {
        if (key == LogicalKeyboardKey.f1) {
          showDialog(context: context, builder: (_) => SettingsPanel());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      builder: (context) => RepaintBoundary(
        key: _screenshotBoundaryKey,
        child: FocusTraversalGroup(
          policy: PageAwareTraversalPolicy(this),
          child: Stack(
            children: [
              Consumer<WallpaperService>(
                builder: (_, wallpaper, __) =>
                    _wallpaper(context, wallpaper.wallpaperBytes, wallpaper.gradient.gradient),
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
        ),
      ),
    );
  }

  KeyEventResult _handleGlobalRemoteBinding(BuildContext context, RawKeyEvent event) {
    if (event is! RawKeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final data = event.data;
    if (data is! RawKeyEventDataAndroid) {
      return KeyEventResult.ignored;
    }
    return _handleGlobalRemoteBindingKeyData(context, keyCode: data.keyCode, scanCode: data.scanCode);
  }

  KeyEventResult _handleGlobalRemoteBindingKeyData(
    BuildContext context, {
    required int keyCode,
    required int scanCode,
  }) {
    final settings = context.read<SettingsService>();
    final binding = settings.remoteBindingForAndroidKeyEvent(keyCode: keyCode, scanCode: scanCode);
    if (binding == null) {
      return KeyEventResult.ignored;
    }

    switch (binding.type) {
      case RemoteBindingType.openSettings:
        showDialog(context: context, builder: (_) => SettingsPanel());
        return KeyEventResult.handled;
      case RemoteBindingType.openAndroidSettings:
        () async {
          await context.read<AppsService>().openSettings();
        }();
        return KeyEventResult.handled;
      case RemoteBindingType.openWifiSettings:
        () async {
          await context.read<AppsService>().openWifiSettings();
        }();
        return KeyEventResult.handled;
      case RemoteBindingType.takeScreenshot:
        () async {
          await _takeScreenshot(context);
        }();
        return KeyEventResult.handled;
      case RemoteBindingType.launchApp:
        final packageName = binding.packageName;
        if (packageName == null || packageName.isEmpty) {
          return KeyEventResult.handled;
        }
        () async {
          await context.read<AppsService>().fLauncherChannel.launchApp(packageName);
        }();
        return KeyEventResult.handled;
      case RemoteBindingType.navigateUp:
      case RemoteBindingType.navigateDown:
      case RemoteBindingType.navigateLeft:
      case RemoteBindingType.navigateRight:
      case RemoteBindingType.select:
      case RemoteBindingType.back:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _takeScreenshot(BuildContext context) async {
    final boundaryContext = _screenshotBoundaryKey.currentContext;
    if (boundaryContext == null) {
      return;
    }
    final renderObject = boundaryContext.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is! RenderRepaintBoundary) {
      return;
    }

    final image = await renderObject.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    if (byteData == null) {
      return;
    }
    final bytes = byteData.buffer.asUint8List();

    final dir = await getExternalStorageDirectory();
    if (dir == null) {
      return;
    }
    final fileName = 'flauncher_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved screenshot to ${file.path}')),
    );
  }

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

  /// Shows a confirmation dialog before shutting down the device
  void _showShutdownDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Shutdown Device'),
          content: Text('Are you sure you want to shutdown the device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                // Close the confirmation dialog
                Navigator.of(context).pop();
                
                // Show the shutdown progress dialog with a timeout
                bool shutdownCompleted = false;
                bool dialogDismissed = false;
                
                // Show a loading dialog with a forced shutdown option
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext dialogContext) {
                    // Start a timer to update the UI and eventually show force option
                    int secondsElapsed = 0;
                    Timer.periodic(Duration(seconds: 1), (timer) {
                      if (shutdownCompleted || dialogDismissed) {
                        timer.cancel();
                        return;
                      }
                      
                      secondsElapsed++;
                      if (secondsElapsed >= 10 && dialogContext.mounted) {
                        // After 10 seconds, if the dialog is still showing, dismiss it and show error
                        timer.cancel();
                        dialogDismissed = true;
                        Navigator.of(dialogContext).pop();
                        
                        // Show the force shutdown option
                        _showForceShutdownDialog(context);
                      }
                    });
                    
                    return AlertDialog(
                      title: Text('Shutting Down'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Attempting to shutdown the device...'),
                          SizedBox(height: 8),
                          Text('Please wait', style: TextStyle(fontStyle: FontStyle.italic)),
                        ],
                      ),
                    );
                  },
                );
                
                try {
                  // Attempt to shut down using all available methods
                  final result = await context.read<AppsService>().fLauncherChannel.shutdownDevice();
                  shutdownCompleted = true;
                  
                  // If we get here and the result is false, the shutdown failed
                  if (!result && !dialogDismissed && context.mounted) {
                    dialogDismissed = true;
                    Navigator.of(context).pop(); // Close the loading dialog if it's still open
                    
                    // Show the force shutdown option
                    _showForceShutdownDialog(context);
                  }
                  // If successful, the device should be shutting down now
                } catch (e) {
                  // Handle any exceptions
                  if (!dialogDismissed && context.mounted) {
                    dialogDismissed = true;
                    Navigator.of(context).pop(); // Close the loading dialog
                    
                    // Show error with force shutdown option
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Error'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Failed to shutdown: ${e.toString()}'),
                              SizedBox(height: 16),
                              Text('Would you like to try force shutdown?'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('CANCEL'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _attemptForceShutdown(context);
                              },
                              child: Text('FORCE SHUTDOWN'),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                            ),
                          ],
                        );
                      },
                    );
                  }
                }
              },
              child: Text('SHUTDOWN'),
            ),
          ],
        );
      },
    );
  }
  
  /// Shows a dialog offering force shutdown options when normal shutdown fails
  void _showForceShutdownDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _attemptForceShutdown(context);
              },
              child: Text('FORCE SHUTDOWN'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        );
      },
    );
  }
  
  /// Attempts more aggressive force shutdown methods
  void _attemptForceShutdown(BuildContext context) {
    // Show a progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Attempting force shutdown...'),
              SizedBox(height: 8),
              Text('This may take a few moments', style: TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
        );
      },
    );
    
    // Try to force shutdown using all available methods
    // This will call the same method but the native code will try more aggressive approaches
    context.read<AppsService>().fLauncherChannel.shutdownDevice().then((success) {
      // If we get here, the shutdown failed
      if (context.mounted) {
        Navigator.of(context).pop(); // Close the progress dialog
        
        // Show final error message
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Force Shutdown Failed'),
              content: Text('Unable to force shutdown the device. You may need to manually power off the device using the physical power button.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      }
    }).catchError((error) {
      // Handle any exceptions
      if (context.mounted) {
        Navigator.of(context).pop(); // Close the progress dialog
        
        // Show error message
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Error'),
              content: Text('An error occurred during force shutdown: $error'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      }
    });
  }
}
