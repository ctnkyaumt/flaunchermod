import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/settings/backup_restore_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FLauncherDatabase database;
  late SettingsService settings;
  late ButtonMappingService mappings;
  late _MemoryWallpaper wallpaper;
  late _BackupChannel channel;
  late AppsService apps;
  late Directory workRoot, directory, documents, downloads;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    workRoot = await Directory('temp_work').absolute.create(recursive: true);
    directory = await workRoot.createTemp('backup_ui_');
    documents = await Directory('${directory.path}/documents').create();
    downloads = await Directory('${directory.path}/downloads').create();
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _BackupPaths(documents.path, downloads.path);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    database = FLauncherDatabase.inMemory();
    await database.insertCategory(CategoriesCompanion.insert(id: Value(777), name: 'Original', order: 0));
    channel = _BackupChannel();
    settings = SettingsService(preferences);
    mappings = ButtonMappingService(preferences, channel);
    wallpaper = _MemoryWallpaper();
    apps = AppsService(channel, database);
    final initialized = Completer<void>();
    apps.addListener(() {
      if (apps.initialized && !initialized.isCompleted) initialized.complete();
    });
    if (!apps.initialized) await initialized.future.timeout(Duration(seconds: 5));
  });

  tearDown(() async {
    apps.dispose();
    mappings.dispose();
    wallpaper.dispose();
    settings.dispose();
    await database.close();
    PathProviderPlatform.instance = previousPaths;
    expect(directory.absolute.path.startsWith(workRoot.path + Platform.pathSeparator), isTrue);
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherDatabase>.value(value: database),
        Provider<SettingsService>.value(value: settings),
        Provider<ButtonMappingService>.value(value: mappings),
        Provider<WallpaperService>.value(value: wallpaper),
        Provider<AppsService>.value(value: apps),
      ],
      child: MaterialApp(home: BackupRestorePanelPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String name) async {
    await tester.tap(find.text('Restore from Backup'));
    await _pumpUntil(tester, () => find.text('Select Backup').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('Cancel closes the merged picker without another picker or restore', (tester) async {
    await tester.runAsync(() async {
      await File('${documents.path}/flauncher_backup_private.json').writeAsString(_backup('Private'));
      await File('${downloads.path}/flauncher_backup_public.json').writeAsString(_backup('Public'));
    });
    await open(tester);
    await tester.tap(find.text('Restore from Backup'));
    await _pumpUntil(tester, () => find.text('Select Backup').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('flauncher_backup_private.json'), findsOneWidget);
    expect(find.text('flauncher_backup_public.json'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Restore Backup?'), findsNothing);
    expect(channel.applicationChecks, 0);
    expect(apps.categoriesWithApps.any((item) => item.category.name == 'Original'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Repeated restore taps open one picker and cancellation unlocks it', (tester) async {
    await open(tester);
    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Restore from Backup'));
    tile.onTap!();
    tile.onTap!();
    await _pumpUntil(tester, () => find.text('Select Backup').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Restore from Backup'));
    await _pumpUntil(tester, () => find.text('Select Backup').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Restore needs confirmation and immediately refreshes the layout cache', (tester) async {
    const name = 'flauncher_backup_restore.json';
    await tester.runAsync(() => File('${documents.path}/$name').writeAsString(_backup('Restored')));
    await open(tester);
    await select(tester, name);
    expect(find.text('Restore Backup?'), findsOneWidget);
    expect(apps.categoriesWithApps.any((item) => item.category.name == 'Original'), isTrue);
    expect(settings.use24HourTimeFormat, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(apps.categoriesWithApps.any((item) => item.category.name == 'Original'), isTrue);
    expect(settings.use24HourTimeFormat, isTrue);

    await select(tester, name);
    await tester.tap(find.text('Restore'));
    await _pumpUntil(tester, () => find.text('Restore completed successfully').evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    expect(apps.categoriesWithApps.map((item) => item.category.name), ['Restored']);
    expect(settings.use24HourTimeFormat, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duplicate backup names select the newest file across directories', (tester) async {
    const name = 'flauncher_backup_duplicate.json';
    await tester.runAsync(() async {
      final old = await File('${documents.path}/$name').writeAsString(_backup('Older'));
      final newer = await File('${downloads.path}/$name').writeAsString(_backup('Newest'));
      await old.setLastModified(DateTime(2024));
      await newer.setLastModified(DateTime(2025));
    });
    await open(tester);
    await select(tester, name);
    await tester.tap(find.text('Restore'));
    await _pumpUntil(tester, () => find.text('Restore completed successfully').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(apps.categoriesWithApps.map((item) => item.category.name), ['Newest']);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 200 && !ready(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: 10)));
    await tester.pump(Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Backup flow did not reach the expected state');
}

String _backup(String name) => jsonEncode({
  'version': 1,
  'settings': {'use24HourTimeFormat': false},
  'categories': [{'id': 777, 'name': name, 'order': 0}],
  'apps': [],
  'appsCategories': [],
});

class _BackupPaths extends PathProviderPlatform {
  final String documents, downloads;
  _BackupPaths(this.documents, this.downloads);
  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
  @override
  Future<String?> getDownloadsPath() async => downloads;
}

class _BackupChannel extends FLauncherChannel {
  int applicationChecks = 0;
  @override
  Future<List<dynamic>> getApplications() async => [];
  @override
  Future<bool> applicationExists(String packageName) async {
    applicationChecks++;
    return false;
  }
  @override
  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) {}
  @override
  Future<bool> isButtonMapperEnabled() async => false;
  @override
  Future<Map<dynamic, dynamic>> rawInputStatus() async => {};
  @override
  Future<void> notifyButtonMappingsChanged() async {}
  @override
  Future<List<dynamic>> listBackupJsonInDownloads() async => [];
}

class _MemoryWallpaper extends ChangeNotifier implements WallpaperService {
  @override
  Future<Uint8List?> exportWallpaper() async => null;
  @override
  Future<void> restoreWallpaper(Uint8List? value) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
