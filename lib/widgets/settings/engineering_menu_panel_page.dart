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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/material.dart';

/// Opens the TV maker's hidden Design and Factory menus (MediaTek/Vestel TVs).
class EngineeringMenuPanelPage extends StatefulWidget {
  static const String routeName = "engineering_menu_panel";

  const EngineeringMenuPanelPage({Key? key}) : super(key: key);

  @override
  State<EngineeringMenuPanelPage> createState() => _EngineeringMenuPanelPageState();
}

class _EngineeringMenuPanelPageState extends State<EngineeringMenuPanelPage> {
  final FLauncherChannel _channel = FLauncherChannel();
  bool _opening = false;

  Future<void> _open(String menu, String title) async {
    if (_opening) return;
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await _channel.openEngineeringMenu(menu);
    } catch (_) {
      opened = false;
    }
    if (mounted) setState(() => _opening = false);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not open $title")));
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          children: [
            Text("Engineering Menu", style: Theme.of(context).textTheme.titleLarge),
            Divider(),
            TextButton(
              autofocus: true,
              child: _entry(context, Icons.tune, "Design Menu", "Diagnostics, panel, audio"),
              onPressed: () => _open("design", "Design Menu"),
            ),
            TextButton(
              child: _entry(context, Icons.build_outlined, "Factory Menu", null),
              onPressed: () => _open("factory", "Factory Menu"),
            ),
          ],
        ),
      );

  Widget _entry(BuildContext context, IconData icon, String title, String? subtitle) => Row(
        children: [
          Icon(icon),
          Container(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                if (subtitle != null) Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
}
