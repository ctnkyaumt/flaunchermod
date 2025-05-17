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
