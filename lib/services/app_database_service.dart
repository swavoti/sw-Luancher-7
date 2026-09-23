import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:installed_apps/app_category.dart';

class AppDatabaseService {
  static Database? _database;

  static final Map<String, Uint8List> _iconCache = {};
  static const int _iconCacheMax = 64;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDb();
    return _database!;
  }

  static Future<Database> initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'apps_cache.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE apps(
            packageName TEXT PRIMARY KEY,
            name TEXT,
            icon BLOB
          )
        ''');
      },
    );
  }

  /// Fast cold-start path: loads only package names and display names.
  ///
  /// Icons are intentionally omitted (icon == null) so the UI can render
  /// immediately without decoding every blob. Fetch icons lazily via
  /// [loadIcon] / [getCachedIcon].
  static Future<List<AppInfo>> getAppMetadata() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'apps',
      columns: ['packageName', 'name'],
    );

    return List.generate(maps.length, (i) {
      return AppInfo(
        name: maps[i]['name'] as String,
        icon: null,
        packageName: maps[i]['packageName'] as String,
        versionName: "",
        versionCode: 0,
        platformType: PlatformType.nativeOrOthers,
        installedTimestamp: 0,
        isSystemApp: false,
        isLaunchableApp: true,
        category: AppCategory.undefined,
      );
    });
  }

  /// Returns the cached icon blob for [packageName], or null if not cached.
  static Uint8List? getCachedIcon(String packageName) {
    return _iconCache[packageName];
  }

  /// Loads the icon blob for [packageName], consulting a bounded in-memory
  /// cache first and falling back to a single-row SQLite query.
  static Future<Uint8List?> loadIcon(String packageName) async {
    final cached = _iconCache[packageName];
    if (cached != null) return cached;

    final db = await database;
    final rows = await db.query(
      'apps',
      columns: ['icon'],
      where: 'packageName = ?',
      whereArgs: [packageName],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final blob = rows.first['icon'] as Uint8List?;
    if (blob == null) return null;

    if (_iconCache.length >= _iconCacheMax) {
      _iconCache.remove(_iconCache.keys.first);
    }
    _iconCache[packageName] = blob;
    return blob;
  }

  /// Instantly get all apps from the local SQLite cache, including icons.
  @Deprecated('Use getAppMetadata() for cold start and loadIcon() lazily.')
  static Future<List<AppInfo>> getAllApps() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('apps');

    return List.generate(maps.length, (i) {
      return AppInfo(
        name: maps[i]['name'] as String,
        icon: maps[i]['icon'],
        packageName: maps[i]['packageName'] as String,
        versionName: "",
        versionCode: 0,
        platformType: PlatformType.nativeOrOthers,
        installedTimestamp: 0,
        isSystemApp: false,
        isLaunchableApp: true,
        category: AppCategory.undefined,
      );
    });
  }

  /// Scan system for apps in background and update the SQLite cache
  /// Returns the updated list of apps
  static Future<List<AppInfo>> syncAppsBackground() async {
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        excludeNonLaunchableApps: true,
        withIcon: true,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final db = await database;
      final batch = db.batch();

      // Clear the table and insert the new list
      // We do this to handle uninstalled apps easily
      batch.delete('apps');
      for (final app in apps) {
        batch.insert('apps', {
          'packageName': app.packageName,
          'name': app.name,
          'icon': app.icon,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);

      // Icons may have changed on disk; drop stale cached blobs.
      _iconCache.clear();

      return apps;
    } catch (e) {
      debugPrint('Error syncing apps: $e');
      return [];
    }
  }
}
