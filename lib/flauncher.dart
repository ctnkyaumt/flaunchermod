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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class FLauncher extends StatefulWidget {
  @override
  _FLauncherState createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  FocusNode? _lastFocusedAppNode;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
        if (page == 1) {
          // Give the page time to build, then focus the first HDMI input
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final scope = FocusManager.instance.primaryFocus?.nearestScope;
            if (scope != null) {
              final nodes = scope.traversalDescendants.toList();
              if (nodes.isNotEmpty) {
                nodes.first.requestFocus();
              }
            }
          });
        } else if (page == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_lastFocusedAppNode != null && _lastFocusedAppNode!.attached) {
              _lastFocusedAppNode!.requestFocus();
            } else {
              final scope = FocusManager.instance.primaryFocus?.nearestScope;
              if (scope != null) {
                final nodes = scope.traversalDescendants.toList();
                if (nodes.isNotEmpty) {
                  nodes.first.requestFocus();
                }
              }
            }
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("FLauncher: Building main UI widget");
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: false,
      onKey: (event) => _handleKeyEvent(event),
      child: FocusTraversalGroup(
        policy: RowByRowTraversalPolicy(),
        child: Stack(
          children: [
            Consumer<WallpaperService>(
              builder: (_, wallpaper, __) => _wallpaper(context, wallpaper.wallpaperBytes, wallpaper.gradient.gradient),
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
    );
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    final key = event.logicalKey;
    
    // Handle page navigation
    if (key == LogicalKeyboardKey.arrowDown && _currentPage == 0) {
      // Check if we're on the bottom row of the Apps page
      final focusNode = FocusManager.instance.primaryFocus;
      if (focusNode != null && _isOnBottomRow(focusNode)) {
        _lastFocusedAppNode = focusNode;
        _navigateToPage(1);
      }
    } else if (key == LogicalKeyboardKey.arrowUp && _currentPage == 1) {
      // Navigate back to Apps page from Inputs page
      _navigateToPage(0);
    }
  }

  bool _isOnBottomRow(FocusNode currentNode) {
    final scope = currentNode.nearestScope;
    if (scope == null) return false;

    final allNodes = scope.traversalDescendants.toList();
    if (allNodes.isEmpty) return false;

    // Find the maximum Y position (bottom-most row)
    double maxY = allNodes.map((node) => node.rect.center.dy).reduce((a, b) => a > b ? a : b);
    
    // Check if current node is on the bottom row (within 5 pixels tolerance)
    return (currentNode.rect.center.dy - maxY).abs() <= 5;
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
        actions: [
          // Spacer to push elements to the right
          Spacer(),
          
          // Shutdown button
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
          
          // Wi-Fi button
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
          
          // Settings button
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
          
          // Time display
          Container(
            margin: EdgeInsets.only(left: 16, right: 32),
            alignment: Alignment.center,
            height: 56, // Match AppBar default height
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
