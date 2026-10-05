import 'dart:typed_data';
import 'dart:async';

import "package:swavoti/services/launcher_service.dart";
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
  static const int _maxIconCacheBytes = 32 << 20;
  static int _iconCacheBytes = 0;
  static int _iconCacheGeneration = 0;
  static String currentIconPack = "";
  static final Map<String, Future<Uint8List?>> _inflight = {};

  static final List<void Function()> _taskQueue = [];
  static int _runningTasks = 0;
  static const int _maxConcurrentTasks = 3;

  static Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _taskQueue.add(() async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      } finally {
        _runningTasks--;
        _pumpQueue();
      }
    });
    _pumpQueue();
    return completer.future;
  }

  static void _pumpQueue() {
    while (_runningTasks < _maxConcurrentTasks && _taskQueue.isNotEmpty) {
      _runningTasks++;
      final next = _taskQueue.removeAt(0);
      next();
    }
  }

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
      version: 3,
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
        await db.execute('''
          CREATE TABLE IF NOT EXISTS apps(
            packageName TEXT PRIMARY KEY,
            name TEXT,
            icon BLOB
          )
        ''');
        final columns = await db.rawQuery('PRAGMA table_info(apps)');
        if (!columns.any((column) => column['name'] == 'icon')) {
          await db.execute('ALTER TABLE apps ADD COLUMN icon BLOB');
        }
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
      await deleteDatabase(path);
      _iconCache.clear();
      _iconCacheBytes = 0;
      _inflight.clear();
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
    final icon = _iconCache.remove(packageName);
    if (icon != null) _iconCache[packageName] = icon;
    return icon;
  }

  static void _cacheIcon(String packageName, Uint8List icon) {
    final previous = _iconCache.remove(packageName);
    if (previous != null) _iconCacheBytes -= previous.lengthInBytes;
    if (icon.lengthInBytes > _maxIconCacheBytes) return;

    _iconCache[packageName] = icon;
    _iconCacheBytes += icon.lengthInBytes;
    while (_iconCacheBytes > _maxIconCacheBytes) {
      final oldestPackage = _iconCache.keys.first;
      _iconCacheBytes -= _iconCache.remove(oldestPackage)!.lengthInBytes;
    }
  }

  static void _removeCachedIcon(String packageName) {
    final icon = _iconCache.remove(packageName);
    if (icon != null) _iconCacheBytes -= icon.lengthInBytes;
  }

  static Future<Uint8List?> loadIcon(String packageName) {
    final cached = getCachedIcon(packageName);
    if (cached != null) return Future.value(cached);

    final iconPack = currentIconPack;
    final cacheGeneration = _iconCacheGeneration;
    final inflightKey = '$packageName\u0000$iconPack\u0000$cacheGeneration';
    return _inflight.putIfAbsent(inflightKey, () async {
      Database? db;
      Uint8List? blob;
      try {
        db = await database;
        final rows = await db.query(
          'apps',
          columns: ['icon'],
          where: 'packageName = ?',
          whereArgs: [packageName],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          blob = rows.first['icon'] as Uint8List?;
        }
      } catch (e) {
        debugPrint(
          'AppDatabaseService.loadIcon cache read error for $packageName: $e',
        );
      }

      if (iconPack.isNotEmpty) {
        try {
          final themed = await _enqueue(
            () => LauncherService.getThemedIcon(packageName, iconPack),
          );
          if (themed != null) blob = themed;
        } catch (e) {
          debugPrint(
            'AppDatabaseService themed icon error for $packageName: $e',
          );
        }
      }
      if (blob == null || blob.isEmpty) {
        try {
          final appInfo = await _enqueue(
            () => InstalledApps.getAppInfo(packageName),
          );
          final osIcon = appInfo?.icon;
          if (osIcon != null && osIcon.isNotEmpty) {
            blob = osIcon;
            if (db != null) {
              try {
                await _persistIcon(db, packageName, osIcon);
              } catch (e) {
                debugPrint(
                  'AppDatabaseService.loadIcon cache write error for $packageName: $e',
                );
              }
            }
          }
        } catch (e) {
          debugPrint('AppDatabaseService OS icon error for $packageName: $e');
        }
      }

      try {
        if (blob == null || blob.isEmpty) return null;

        if (cacheGeneration == _iconCacheGeneration) {
          _cacheIcon(packageName, blob);
        }
        return blob;
      } finally {
        _inflight.remove(inflightKey);
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
  static Future<void> clearIconCache() async {
    _iconCacheGeneration++;
    _iconCache.clear();
    _iconCacheBytes = 0;
    _inflight.clear();
    try {
      final db = await database;
      await db.execute('UPDATE apps SET icon = NULL');
    } catch (e) {
      debugPrint('Error clearing icon cache: $e');
    }
  }

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

    await Future.wait(List.generate(6, (_) => worker()));
  }

  static Future<void> cacheApps(List<AppInfo> apps) async {
    try {
      final db = await database;
      final existing = await db.query('apps', columns: ['packageName']);
      final existingPackages = existing
          .map((row) => row['packageName'] as String)
          .toSet();
      final freshPackages = apps.map((app) => app.packageName).toSet();
      final batch = db.batch();

      for (final packageName in existingPackages.difference(freshPackages)) {
        batch.delete(
          'apps',
          where: 'packageName = ?',
          whereArgs: [packageName],
        );
        _removeCachedIcon(packageName);
      }
      for (final app in apps) {
        if (existingPackages.contains(app.packageName)) {
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
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('AppDatabaseService.cacheApps error: $e');
    }
  }

  /// Refresh the installed-app list. Existing icon blobs are kept.
  static Future<List<AppInfo>> syncAppsBackground() async {
    List<AppInfo> apps;
    try {
      apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        excludeNonLaunchableApps: true,
        withIcon: false,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      debugPrint('AppDatabaseService OS app scan error: $e');
      return [];
    }

    await cacheApps(apps);
    return apps;
  }
}
