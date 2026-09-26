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
  static final Map<String, Future<Uint8List?>> _inflight = {};

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await initDb();
    return _database!;
  }

  static Future<Database> initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'apps_cache.db');

    Future<Database> open() => openDatabase(
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
      return await open();
    } catch (e) {
      debugPrint(
        'AppDatabaseService: Failed to open DB ($e) — deleting and recreating',
      );
      try {
        File(path).deleteSync();
      } catch (_) {}
      _iconCache.clear();
      return await open();
    }
  }

  /// Fast cold-start path: names only. Icons stay in SQLite and memory.
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

  static Uint8List? getCachedIcon(String packageName) {
    return _iconCache[packageName];
  }

  static Future<Uint8List?> loadIcon(String packageName) {
    final cached = _iconCache[packageName];
    if (cached != null) return Future.value(cached);

    return _inflight.putIfAbsent(packageName, () async {
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

        if (blob == null || blob.isEmpty) {
          try {
            final appInfo = await InstalledApps.getAppInfo(packageName);
            if (appInfo != null &&
                appInfo.icon != null &&
                appInfo.icon!.isNotEmpty) {
              blob = appInfo.icon;
              await _persistIcon(db, packageName, blob!);
            }
          } catch (_) {}
        }

        if (blob == null || blob.isEmpty) return null;

        _iconCache[packageName] = blob;
        return blob;
      } catch (e) {
        debugPrint('AppDatabaseService.loadIcon error for $packageName: $e');
        return null;
      } finally {
        _inflight.remove(packageName);
      }
    });
  }

  static Future<void> _persistIcon(
    Database db,
    String packageName,
    Uint8List blob,
  ) async {
    final updated = await db.update(
      'apps',
      {'icon': blob},
      where: 'packageName = ?',
      whereArgs: [packageName],
    );
    if (updated == 0) {
      await db.insert('apps', {
        'packageName': packageName,
        'name': packageName,
        'icon': blob,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.update(
        'apps',
        {'icon': blob},
        where: 'packageName = ?',
        whereArgs: [packageName],
      );
    }
  }

  /// Warm SQLite + memory for every listed package, a few at a time.
  static Future<void> prefetchIcons(Iterable<String> packageNames) async {
    final pending = packageNames
        .where((p) => !_iconCache.containsKey(p) && !_inflight.containsKey(p))
        .toList();
    if (pending.isEmpty) return;

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length) {
        final index = cursor++;
        await loadIcon(pending[index]);
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
  }

  /// Refresh the installed-app list. Existing icon blobs are kept.
  static Future<List<AppInfo>> syncAppsBackground() async {
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        excludeNonLaunchableApps: true,
        withIcon: false,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final db = await database;
      final existing = await db.query('apps', columns: ['packageName', 'icon']);
      final existingIcons = <String, Uint8List?>{};
      for (final row in existing) {
        existingIcons[row['packageName'] as String] = row['icon'] as Uint8List?;
      }

      final fresh = apps.map((a) => a.packageName).toSet();
      final batch = db.batch();

      for (final pkg in existingIcons.keys) {
        if (!fresh.contains(pkg)) {
          batch.delete('apps', where: 'packageName = ?', whereArgs: [pkg]);
          _iconCache.remove(pkg);
        }
      }

      for (final app in apps) {
        final keptIcon = existingIcons[app.packageName];
        if (existingIcons.containsKey(app.packageName)) {
          batch.update(
            'apps',
            {'name': app.name},
            where: 'packageName = ?',
            whereArgs: [app.packageName],
          );
        } else {
          batch.insert('apps', {
            'packageName': app.packageName,
            'name': app.name,
            'icon': keptIcon,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      await batch.commit(noResult: true);

      prefetchIcons(apps.map((a) => a.packageName));
      return apps;
    } catch (e) {
      debugPrint('AppDatabaseService.syncAppsBackground error: $e');
      return [];
    }
  }
}
