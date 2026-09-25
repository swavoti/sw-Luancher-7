import 'dart:typed_data';
import 'dart:io';

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
  static const int _iconCacheMax = 128;

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await initDb();
    return _database!;
  }

  static Future<Database> initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'apps_cache.db');

    Future<Database> _open() => openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS apps(
            packageName TEXT PRIMARY KEY,
            name TEXT,
            icon BLOB
          )
        ''');
        await db.execute('PRAGMA journal_mode=WAL');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('PRAGMA journal_mode=WAL');
      },
      onOpen: (db) async {
        await db.execute('PRAGMA journal_mode=WAL');
        // Integrity check — if corrupt, nuke and recreate table
        try {
          final result = await db.rawQuery('PRAGMA integrity_check');
          final ok =
              result.isNotEmpty && result.first.values.first.toString() == 'ok';
          if (!ok) {
            debugPrint('AppDatabaseService: DB corrupt — dropping table');
            await db.execute('DROP TABLE IF EXISTS apps');
            await db.execute('''
              CREATE TABLE apps(
                packageName TEXT PRIMARY KEY,
                name TEXT,
                icon BLOB
              )
            ''');
          }
        } catch (e) {
          debugPrint('AppDatabaseService: integrity check failed: $e');
        }
      },
    );

    try {
      return await _open();
    } catch (e) {
      // If we can't open at all, delete and recreate
      debugPrint(
        'AppDatabaseService: Failed to open DB ($e) — deleting and recreating',
      );
      try {
        File(path).deleteSync();
      } catch (_) {}
      _iconCache.clear();
      return await _open();
    }
  }

  /// Fast cold-start path: loads only package names and display names.
  /// Icons are loaded lazily via [loadIcon].
  static Future<List<AppInfo>> getAppMetadata() async {
    try {
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
    } catch (e) {
      debugPrint('AppDatabaseService.getAppMetadata error: $e');
      return [];
    }
  }

  /// Returns the in-memory cached icon for [packageName], or null.
  static Uint8List? getCachedIcon(String packageName) {
    return _iconCache[packageName];
  }

  /// Loads the icon blob for [packageName], checking the in-memory cache
  /// Load an icon from memory cache, database, or lazily fetch from the OS.
  static Future<Uint8List?> loadIcon(String packageName) async {
    final cached = _iconCache[packageName];
    if (cached != null) return cached;

    try {
      final db = await database;
      final rows = await db.query(
        'apps',
        columns: ['icon'],
        where: 'packageName = ?',
        whereArgs: [packageName],
        limit: 1,
      );

      Uint8List? blob;
      if (rows.isNotEmpty) {
        blob = rows.first['icon'] as Uint8List?;
      }

      // Lazy fetch icon if not in database
      if (blob == null || blob.isEmpty) {
        try {
          final appInfo = await InstalledApps.getAppInfo(packageName);
          if (appInfo != null &&
              appInfo.icon != null &&
              appInfo.icon!.isNotEmpty) {
            blob = appInfo.icon;
            // Cache it in SQLite for next time
            await db.update(
              'apps',
              {'icon': blob},
              where: 'packageName = ?',
              whereArgs: [packageName],
            );
          }
        } catch (_) {}
      }

      if (blob == null || blob.isEmpty) return null;

      if (_iconCache.length >= _iconCacheMax) {
        _iconCache.remove(_iconCache.keys.first);
      }
      _iconCache[packageName] = blob;
      return blob;
    } catch (e) {
      debugPrint('AppDatabaseService.loadIcon error for $packageName: $e');
      return null;
    }
  }

  /// Scan system for installed apps in the background, update SQLite cache.
  /// Returns the updated list instantly without icons (icons are lazy-loaded).
  static Future<List<AppInfo>> syncAppsBackground() async {
    try {
      // Fetch list without icons to prevent TransactionTooLargeException and keep it ultra-fast
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        excludeNonLaunchableApps: true,
        withIcon: false,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final db = await database;
      final batch = db.batch();

      batch.delete('apps');

      for (final app in apps) {
        batch.insert('apps', {
          'packageName': app.packageName,
          'name': app.name,
          'icon': null, // Icons will be populated lazily
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
      _iconCache.clear();

      return apps;
    } catch (e) {
      debugPrint('AppDatabaseService.syncAppsBackground error: $e');
      return [];
    }
  }
}
