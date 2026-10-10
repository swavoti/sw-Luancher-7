import 'dart:typed_data';
import 'dart:async';

import "package:swavoti/services/launcher_service.dart";
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/platform_type.dart';
import 'package:installed_apps/app_category.dart';

class AppDatabaseService {
  static Database? _database;

  static final Map<String, Uint8List> _iconCache = {};
  static final Map<String, MemoryImage> _memoryImageCache = {};
  static bool _lightweightMode = false;
  static int get _maxIconCacheBytes => _lightweightMode ? 8 << 20 : 32 << 20;
  static int _iconCacheBytes = 0;
  static int _iconCacheGeneration = 0;
  static String currentIconPack = "";
  static final Map<String, Future<Uint8List?>> _inflight = {};

  static final List<void Function()> _taskQueue = [];
  static int _runningTasks = 0;
  static int get _maxConcurrentTasks => _lightweightMode ? 1 : 4;

  static void setLightweightMode(bool enabled) {
    _lightweightMode = enabled;
    while (_iconCacheBytes > _maxIconCacheBytes && _iconCache.isNotEmpty) {
      final oldestPackage = _iconCache.keys.first;
      _iconCacheBytes -= _iconCache.remove(oldestPackage)!.lengthInBytes;
      _memoryImageCache.remove(oldestPackage);
    }
    _pumpQueue();
  }

  static void clearMemoryIconCache() {
    _iconCache.clear();
    _memoryImageCache.clear();
    _iconCacheBytes = 0;
  }

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

    Future<void> ensureColumns(Database db) async {
      final columns = await db.rawQuery('PRAGMA table_info(apps)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      if (!columnNames.contains('os_icon')) {
        await db.execute('ALTER TABLE apps ADD COLUMN os_icon BLOB');
      }
      if (!columnNames.contains('themed_icon')) {
        await db.execute('ALTER TABLE apps ADD COLUMN themed_icon BLOB');
      }
      if (!columnNames.contains('themed_pack')) {
        await db.execute('ALTER TABLE apps ADD COLUMN themed_pack TEXT');
      }
      if (columnNames.contains('icon')) {
        await db.execute(
          'UPDATE apps SET os_icon = icon WHERE os_icon IS NULL AND icon IS NOT NULL',
        );
      }
    }

    Future<Database> open() => openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS apps(
            packageName TEXT PRIMARY KEY,
            name TEXT,
            os_icon BLOB,
            themed_icon BLOB,
            themed_pack TEXT
          )
        ''');
        await db.execute('PRAGMA journal_mode=WAL');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS apps(
            packageName TEXT PRIMARY KEY,
            name TEXT,
            os_icon BLOB,
            themed_icon BLOB,
            themed_pack TEXT
          )
        ''');
        await ensureColumns(db);
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
                os_icon BLOB,
                themed_icon BLOB,
                themed_pack TEXT
              )
            ''');
          } else {
            await ensureColumns(db);
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
    if (icon != null) {
      _iconCache[packageName] = icon;
      final img = _memoryImageCache.remove(packageName);
      if (img != null) _memoryImageCache[packageName] = img;
    }
    return icon;
  }

  static MemoryImage? getCachedImage(String packageName) {
    final icon = getCachedIcon(packageName);
    if (icon == null) return null;
    return _memoryImageCache.putIfAbsent(packageName, () => MemoryImage(icon));
  }

  static void _cacheIcon(String packageName, Uint8List icon) {
    final previous = _iconCache.remove(packageName);
    if (previous != null) _iconCacheBytes -= previous.lengthInBytes;
    _memoryImageCache.remove(packageName);
    if (icon.lengthInBytes > _maxIconCacheBytes) return;

    _iconCache[packageName] = icon;
    _memoryImageCache[packageName] = MemoryImage(icon);
    _iconCacheBytes += icon.lengthInBytes;
    while (_iconCacheBytes > _maxIconCacheBytes) {
      final oldestPackage = _iconCache.keys.first;
      _iconCacheBytes -= _iconCache.remove(oldestPackage)!.lengthInBytes;
      _memoryImageCache.remove(oldestPackage);
    }
  }

  static void _removeCachedIcon(String packageName) {
    final icon = _iconCache.remove(packageName);
    if (icon != null) _iconCacheBytes -= icon.lengthInBytes;
    _memoryImageCache.remove(packageName);
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
      Map<String, dynamic>? row;
      try {
        db = await database;
        final rows = await db.query(
          'apps',
          columns: ['os_icon', 'themed_icon', 'themed_pack'],
          where: 'packageName = ?',
          whereArgs: [packageName],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          row = rows.first;
        }
      } catch (e) {
        debugPrint(
          'AppDatabaseService.loadIcon cache read error for $packageName: $e',
        );
      }

      final rowThemedPack = row?['themed_pack'] as String?;
      final rowThemedIcon = row?['themed_icon'] as Uint8List?;
      final rowOsIcon = row?['os_icon'] as Uint8List?;

      if (iconPack.isNotEmpty) {
        if (rowThemedPack == iconPack) {
          // This app was already evaluated for the current icon pack!
          if (rowThemedIcon != null && rowThemedIcon.isNotEmpty) {
            blob = rowThemedIcon;
          } else {
            // Pack does not support this app (sentinel NULL). Immediately fallback to OS icon.
            blob = rowOsIcon;
          }
        } else {
          // Needs lookup from the icon pack
          try {
            final themed = await _enqueue(
              () => LauncherService.getThemedIcon(packageName, iconPack),
            );
            if (themed != null && themed.isNotEmpty) {
              blob = themed;
              if (db != null) {
                await _persistThemedIcon(db, packageName, themed, iconPack);
              }
            } else {
              // Mark themed_icon as null with current pack so we never query native again for this app
              if (db != null) {
                await _persistThemedIcon(db, packageName, null, iconPack);
              }
              blob = rowOsIcon;
            }
          } catch (e) {
            debugPrint(
              'AppDatabaseService themed icon error for $packageName: $e',
            );
            blob = rowOsIcon;
          }
        }
      } else {
        blob = rowOsIcon;
      }

      // If OS icon is still needed and was not in SQLite:
      if (blob == null || blob.isEmpty) {
        try {
          final osIcon = await _enqueue(
            () => LauncherService.getOsIcon(packageName),
          );
          if (osIcon != null && osIcon.isNotEmpty) {
            blob = osIcon;
            if (db != null) {
              await _persistOsIcon(db, packageName, osIcon);
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

  static Future<void> _persistThemedIcon(
    Database db,
    String packageName,
    Uint8List? blob,
    String iconPack,
  ) async {
    try {
      final updated = await db.update(
        'apps',
        {'themed_icon': blob, 'themed_pack': iconPack},
        where: 'packageName = ?',
        whereArgs: [packageName],
      );
      if (updated == 0) {
        await db.insert('apps', {
          'packageName': packageName,
          'name': packageName,
          'themed_icon': blob,
          'themed_pack': iconPack,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (e) {
      debugPrint('AppDatabaseService._persistThemedIcon error for $packageName: $e');
    }
  }

  static Future<void> _persistOsIcon(
    Database db,
    String packageName,
    Uint8List blob,
  ) async {
    try {
      final updated = await db.update(
        'apps',
        {'os_icon': blob},
        where: 'packageName = ?',
        whereArgs: [packageName],
      );
      if (updated == 0) {
        await db.insert('apps', {
          'packageName': packageName,
          'name': packageName,
          'os_icon': blob,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (e) {
      debugPrint('AppDatabaseService._persistOsIcon error for $packageName: $e');
    }
  }

  /// Clears in-memory icon caches and resets themed icons in SQLite.
  /// NOTE: os_icon is permanently preserved across icon pack changes!
  static Future<void> clearIconCache() async {
    _iconCacheGeneration++;
    _iconCache.clear();
    _memoryImageCache.clear();
    _iconCacheBytes = 0;
    _inflight.clear();
    try {
      final db = await database;
      await db.execute('UPDATE apps SET themed_icon = NULL, themed_pack = NULL');
    } catch (e) {
      debugPrint('Error clearing icon cache: $e');
    }
  }

  static Future<void> prefetchIcons(Iterable<String> packageNames) async {
    final inflightSuffix = '\u0000$currentIconPack\u0000$_iconCacheGeneration';
    final pending = packageNames
        .where(
          (p) =>
              !_iconCache.containsKey(p) &&
              !_inflight.containsKey('$p$inflightSuffix'),
        )
        .toList();
    if (pending.isEmpty) return;

    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length) {
        final index = cursor++;
        await loadIcon(pending[index]);
      }
    }

    await Future.wait(List.generate(_lightweightMode ? 1 : 6, (_) => worker()));
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
