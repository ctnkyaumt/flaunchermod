import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FLauncherDatabase database;
  late AppsService service;
  setUp(() async {
    database = FLauncherDatabase.inMemory();
    await database.persistApps([
      AppsCompanion.insert(packageName: "missing.app", name: "Missing", version: "", hidden: Value(true)),
      AppsCompanion.insert(packageName: "removed.app", name: "Removed", version: "1", hidden: Value(true)),
    ]);
    await database.insertCategory(CategoriesCompanion.insert(id: Value(1), name: "Saved", order: 0));
    await database.insertAppsCategories([
      AppsCategoriesCompanion.insert(categoryId: 1, appPackageName: "missing.app", order: 3),
    ]);
    service = AppsService(_EmptyChannel(), database);
    final initialized = Completer<void>();
    service.addListener(() {
      if (service.initialized && !initialized.isCompleted) initialized.complete();
    });
    await initialized.future.timeout(Duration(seconds: 5));
  });
  tearDown(() async {
    service.dispose();
    await database.close();
  });

  test("startup retains restored placeholders and assignments but drops uninstalled real apps", () async {
    expect(await database.getApp("missing.app"), isNotNull);
    expect(await database.getApp("removed.app"), isNull);
    final assignments = await database.select(database.appsCategories).get();
    expect(assignments.any((a) => a.categoryId == 1 && a.appPackageName == "missing.app" && a.order == 3), isTrue);
  });

  test("restored layout becomes visible immediately without scanning installed apps", () async {
    final before = service.categoriesWithApps.firstWhere((c) => c.category.id == 1);
    expect(before.category.name, "Saved");
    await database.updateCategory(1, CategoriesCompanion(name: Value("Restored")));

    await service.reloadAfterRestore();

    expect(service.categoriesWithApps.firstWhere((c) => c.category.id == 1).category.name, "Restored");
  });
}

class _EmptyChannel extends FLauncherChannel {
  @override
  Future<List<dynamic>> getApplications() async => [];
  @override
  Future<bool> applicationExists(String packageName) async => false;
  @override
  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) {}
}
