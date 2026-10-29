// ignore_for_file: unnecessary_import

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:ui';

class MediaPlaybackInfo {
  final String packageName;
  final String title;
  final String artist;
  final String album;
  final Uint8List? albumArt;
  final Uint8List? appIcon;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final double playbackSpeed;
  final int updatedAtMs;
  final bool isLocalPlayer;
  final int? localTrackId;

  const MediaPlaybackInfo({
    required this.packageName,
    required this.title,
    required this.artist,
    this.album = '',
    required this.albumArt,
    required this.appIcon,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    this.playbackSpeed = 1.0,
    this.updatedAtMs = 0,
    this.isLocalPlayer = false,
    this.localTrackId,
  });

  int livePositionMs([int? nowEpochMs]) {
    if (!isPlaying) {
      return durationMs > 0 ? positionMs.clamp(0, durationMs) : positionMs;
    }
    final now = nowEpochMs ?? DateTime.now().millisecondsSinceEpoch;
    final anchor = updatedAtMs > 0 ? updatedAtMs : now;
    final elapsed = (now - anchor).clamp(0, 5000);
    final speed = playbackSpeed > 0 ? playbackSpeed : 1.0;
    final extrapolated = positionMs + (elapsed * speed).round();
    return durationMs > 0
        ? extrapolated.clamp(0, durationMs)
        : extrapolated.clamp(0, 999999999);
  }

  factory MediaPlaybackInfo.fromMap(Map<dynamic, dynamic> value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return MediaPlaybackInfo(
      packageName: value['packageName'] as String? ?? '',
      title: value['title'] as String? ?? '',
      artist: value['artist'] as String? ?? '',
      album: value['album'] as String? ?? '',
      albumArt: value['albumArt'] as Uint8List?,
      appIcon: value['appIcon'] as Uint8List?,
      isPlaying: value['isPlaying'] as bool? ?? false,
      positionMs: (value['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (value['durationMs'] as num?)?.toInt() ?? 0,
      playbackSpeed: (value['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      updatedAtMs: now,
      isLocalPlayer: value['isLocalPlayer'] as bool? ?? false,
      localTrackId: (value['localTrackId'] as num?)?.toInt(),
    );
  }
}

class LocalMusicTrack {
  final int id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int sizeBytes;
  final String format;
  final String contentUri;
  final int albumId;
  final int dateAdded;

  const LocalMusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.sizeBytes,
    required this.format,
    required this.contentUri,
    required this.albumId,
    required this.dateAdded,
  });

  factory LocalMusicTrack.fromMap(Map<dynamic, dynamic> map) {
    return LocalMusicTrack(
      id: (map['id'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? 'Unknown Track',
      artist: map['artist'] as String? ?? 'Local Audio',
      album: map['album'] as String? ?? '',
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      format: map['format'] as String? ?? 'MP3',
      contentUri: map['contentUri'] as String? ?? '',
      albumId: (map['albumId'] as num?)?.toInt() ?? 0,
      dateAdded: (map['dateAdded'] as num?)?.toInt() ?? 0,
    );
  }

  String get durationLabel {
    final totalSec = (durationMs ~/ 1000).clamp(0, 359999);
    final mins = totalSec ~/ 60;
    final secs = (totalSec % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return format;
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1.0) {
      return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB [$format]';
    }
    final kb = (sizeBytes / 1024).round();
    return '$kb KB [$format]';
  }
}

class DeviceMemoryInfo {
  final int totalRamBytes;
  final bool isLowRamDevice;

  const DeviceMemoryInfo({
    required this.totalRamBytes,
    required this.isLowRamDevice,
  });

  factory DeviceMemoryInfo.fromMap(Map<dynamic, dynamic> value) {
    return DeviceMemoryInfo(
      totalRamBytes: (value['totalRamBytes'] as num).toInt(),
      isLowRamDevice: value['isLowRamDevice'] as bool,
    );
  }

  bool get shouldRecommendLightweightMode =>
      isLowRamDevice || totalRamBytes <= 3584 * 1024 * 1024;

  String get approximateRamLabel {
    final wholeGigabytes = (totalRamBytes / (1024 * 1024 * 1024)).round();
    return 'About $wholeGigabytes GB RAM';
  }
}

class LauncherService {
  static const _systemChannel = MethodChannel('co.za.launcher3.swavoti/system');
  static const _widgetChannel = MethodChannel(
    'co.za.launcher3.swavoti/widgets',
  );
  static const _notificationChannel = EventChannel(
    'co.za.launcher3.swavoti/notifications',
  );
  static const _mediaChannel = EventChannel('co.za.launcher3.swavoti/media');

  static List<Map<String, dynamic>>? _cachedWidgets;
  static final ValueNotifier<List<LocalMusicTrack>> localTracksNotifier =
      ValueNotifier<List<LocalMusicTrack>>(const []);
  static bool _localTracksLoadedOnce = false;
  static final Map<int, Uint8List?> _localAlbumArtCache = <int, Uint8List?>{};

  static void replaceCachedWidgets(List<Map<String, dynamic>> widgets) {
    _cachedWidgets = widgets;
  }

  static Future<void> preloadWidgets() async {
    if (_cachedWidgets != null) return;
    try {
      final List<dynamic>? widgets = await _widgetChannel.invokeMethod(
        'getAllWidgets',
      );
      if (widgets != null) {
        _cachedWidgets = widgets
            .map((w) => Map<String, dynamic>.from(w as Map))
            .toList();
      }
    } catch (e) {
      print('Error preloading widgets: $e');
    }
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      return await _systemChannel.invokeMethod<bool>('isBiometricAvailable') ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// Shows the system biometric prompt. Returns true only on success.
  static Future<bool> authenticateBiometric({
    String title = 'Unlock',
    String? subtitle,
    String negativeText = 'Use PIN',
  }) async {
    try {
      return await _systemChannel.invokeMethod<bool>('authenticateBiometric', {
            'title': title,
            'subtitle': subtitle,
            'negativeText': negativeText,
          }) ??
          false;
    } catch (e) {
      return false;
    }
  }

  // System Actions
  static Future<List<Map<String, dynamic>>> getAvailableIconPacks() async {
    try {
      final List<dynamic>? packs = await _systemChannel.invokeMethod(
        'getAvailableIconPacks',
      );
      if (packs != null) {
        return packs.map((p) => Map<String, dynamic>.from(p as Map)).toList();
      }
    } catch (e) {
      print('Error fetching icon packs: $e');
    }
    return [];
  }

  /// Batched OS icon lookup: one platform-channel crossing for many packages.
  ///
  /// Returns an empty map when the native handler is missing (older installs),
  /// so callers can fall back to per-icon [getOsIcon].
  static Future<Map<String, Uint8List?>> getOsIcons(
    List<String> packageNames,
  ) async {
    if (packageNames.isEmpty) return const <String, Uint8List?>{};
    try {
      final Map<dynamic, dynamic>? result = await _systemChannel
          .invokeMethod<Map<dynamic, dynamic>>('getOsIcons', {
            'packages': packageNames,
          });
      if (result == null) return const <String, Uint8List?>{};
      return result.map<String, Uint8List?>(
        (key, value) => MapEntry(key as String, value as Uint8List?),
      );
    } catch (e) {
      print('Error fetching OS icons batch: $e');
      return const <String, Uint8List?>{};
    }
  }

  static Future<Uint8List?> getThemedIcon(
    String appPackage,
    String iconPackPackage,
  ) async {
    try {
      return await _systemChannel.invokeMethod('getThemedIcon', {
        'appPackage': appPackage,
        'iconPackPackage': iconPackPackage,
      });
    } catch (e) {
      print('Error fetching themed icon: $e');
      return null;
    }
  }

  static Future<Uint8List?> getOsIcon(String packageName) async {
    try {
      return await _systemChannel.invokeMethod('getOsIcon', {
        'packageName': packageName,
      });
    } catch (e) {
      print('Error fetching OS icon: $e');
      return null;
    }
  }

  static Future<Uint8List?> getMonochromeIcon(String packageName) async {
    try {
      return await _systemChannel.invokeMethod('getMonochromeIcon', {
        'packageName': packageName,
      });
    } catch (e) {
      print('Error fetching monochrome icon: $e');
      return null;
    }
  }

  static Future<void> uninstallApp(String packageName) async {
    try {
      await _systemChannel.invokeMethod('uninstallApp', {
        'packageName': packageName,
      });
    } catch (e) {
      print('Error uninstalling app: $e');
    }
  }

  static Future<void> startApp(
    String packageName, {
    bool splitScreen = false,
    Rect? sourceBounds,
    Rect? returnBounds,
    bool fromDrawer = false,
  }) async {
    try {
      await _systemChannel.invokeMethod('startApp', {
        'packageName': packageName,
        'splitScreen': splitScreen,
        'fromDrawer': fromDrawer,
        if (sourceBounds != null) ...{
          'sourceLeft': sourceBounds.left,
          'sourceTop': sourceBounds.top,
          'sourceWidth': sourceBounds.width,
          'sourceHeight': sourceBounds.height,
          'sourceX': sourceBounds.left.round(),
          'sourceY': sourceBounds.top.round(),
        },
        if (returnBounds != null) ...{
          'returnLeft': returnBounds.left,
          'returnTop': returnBounds.top,
          'returnWidth': returnBounds.width,
          'returnHeight': returnBounds.height,
        },
      });
    } catch (e) {
      print('Error starting app: $e');
    }
  }

  static Future<void> syncHomeScene({
    required bool isCleanHome,
    bool isSubRouteOpen = false,
    String iconShape = 'Circle',
    List<Map<String, dynamic>>? targets,
  }) async {
    try {
      await _systemChannel.invokeMethod('syncHomeScene', {
        'isCleanHome': isCleanHome,
        'isSubRouteOpen': isSubRouteOpen,
        'iconShape': iconShape,
        if (targets != null) 'targets': targets,
      });
    } catch (_) {}
  }

  static Future<void> invalidateCompositorIcons() async {
    try {
      await _systemChannel.invokeMethod('invalidateCompositorIcons');
    } catch (_) {}
  }

  static Future<void> openAppInfo(String packageName) async {
    try {
      await _systemChannel.invokeMethod('appInfo', {
        'packageName': packageName,
      });
    } catch (e) {
      print('Error opening app info: $e');
    }
  }

  static Future<void> changeWallpaper() async {
    try {
      await _systemChannel.invokeMethod('changeWallpaper');
    } catch (e) {
      print('Error changing wallpaper: $e');
    }
  }

  static Future<void> launchGoogleWeather() async {
    try {
      await _systemChannel.invokeMethod('launchGoogleWeather');
    } catch (e) {
      print('Error launching weather: $e');
    }
  }

  static Future<bool> supportsSplitScreen() async {
    try {
      final result = await _systemChannel.invokeMethod<bool>(
        'supportsSplitScreen',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> shareApp(String packageName) async {
    try {
      await _systemChannel.invokeMethod('shareApp', {
        'packageName': packageName,
      });
    } catch (e) {
      print('Error sharing app: $e');
    }
  }

  static Future<bool> setWallpaper(Uint8List imageBytes, int type) async {
    try {
      final bool? success = await _systemChannel.invokeMethod('setWallpaper', {
        'bytes': imageBytes,
        'type': type,
      });
      return success ?? false;
    } catch (e) {
      print('Error setting wallpaper: $e');
      return false;
    }
  }

  static void setWallpaperOffset(double offset) {
    try {
      _systemChannel.invokeMethod('setWallpaperOffset', {'offset': offset});
    } catch (e) {
      print('Error setting wallpaper offset: $e');
    }
  }

  static Future<void> openGoogleDiscover() async {
    try {
      await _systemChannel.invokeMethod('openGoogleDiscover');
    } catch (e) {
      print('Error opening Google Discover: $e');
    }
  }

  static Future<void> expandNotifications() async {
    try {
      await _systemChannel.invokeMethod('expandNotifications');
    } catch (e) {
      print('Error expanding notifications: $e');
    }
  }

  static Future<void> openGoogleVoiceSearch() async {
    try {
      await _systemChannel.invokeMethod('openGoogleVoiceSearch');
    } catch (e) {
      print('Error opening voice search: $e');
    }
  }

  static Future<void> openGoogleAiMode() async {
    try {
      await _systemChannel.invokeMethod('openGoogleAiMode');
    } catch (e) {
      print('Error opening Google AI mode: $e');
    }
  }

  static Future<void> openUrlInBrowser(
    String url, [
    String? packageName,
  ]) async {
    try {
      await _systemChannel.invokeMethod('openUrlInBrowser', {
        'url': url,
        'packageName': packageName,
      });
    } catch (e) {
      print('Error opening URL: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getInstalledBrowsers() async {
    try {
      final List<dynamic>? browsers = await _systemChannel.invokeMethod(
        'getInstalledBrowsers',
      );
      if (browsers != null) {
        return browsers
            .map((b) => Map<String, dynamic>.from(b as Map))
            .toList();
      }
    } catch (e) {
      print('Error getting installed browsers: $e');
    }
    return [];
  }

  static Future<void> openNotificationSettings() async {
    try {
      await _systemChannel.invokeMethod('openNotificationSettings');
    } catch (e) {
      print('Error opening Notification Settings: $e');
    }
  }

  static Future<DeviceMemoryInfo> getDeviceMemoryInfo() async {
    final value = await _systemChannel.invokeMapMethod<String, dynamic>(
      'getDeviceMemoryInfo',
    );
    if (value == null) {
      throw PlatformException(
        code: 'DEVICE_MEMORY_UNAVAILABLE',
        message: 'Android did not return device memory information.',
      );
    }
    return DeviceMemoryInfo.fromMap(value);
  }

  static Stream<MediaPlaybackInfo?> get mediaPlaybackStream {
    return _mediaChannel.receiveBroadcastStream().map((event) {
      return event is Map ? MediaPlaybackInfo.fromMap(event) : null;
    });
  }

  static Future<bool> controlMedia(String action, {int? positionMs}) async {
    return await _systemChannel.invokeMethod<bool>('controlMedia', {
          'action': action,
          if (positionMs != null) 'positionMs': positionMs,
        }) ??
        false;
  }

  static Future<void> showMediaOutputSwitcher() async {
    await _systemChannel.invokeMethod('showMediaOutputSwitcher');
  }

  static Future<bool> openMediaApp(String packageName) async {
    return await _systemChannel.invokeMethod<bool>('launchMediaApp', {
          'packageName': packageName,
        }) ??
        false;
  }

  static Future<bool> hasAudioPermission() async {
    try {
      return await _systemChannel.invokeMethod<bool>('hasAudioPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestAudioPermission() async {
    try {
      return await _systemChannel.invokeMethod<bool>(
            'requestAudioPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<LocalMusicTrack>> getLocalMusicTracks({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _localTracksLoadedOnce) {
      return localTracksNotifier.value;
    }
    try {
      final hasPerm = await hasAudioPermission();
      if (!hasPerm) {
        return localTracksNotifier.value;
      }
      final List<dynamic>? raw = await _systemChannel.invokeMethod(
        'getLocalMusicTracks',
      );
      if (raw != null) {
        final parsed = raw
            .whereType<Map>()
            .map(LocalMusicTrack.fromMap)
            .where((t) => t.id > 0)
            .toList(growable: false);
        _localTracksLoadedOnce = true;
        localTracksNotifier.value = parsed;
        return parsed;
      }
    } catch (e) {
      debugPrint('Error querying local music tracks: $e');
    }
    return localTracksNotifier.value;
  }

  static Uint8List? getCachedLocalAlbumArt(int albumId, int trackId) {
    final key = albumId > 0 ? albumId : -trackId;
    return _localAlbumArtCache[key];
  }

  static Future<Uint8List?> getLocalAlbumArt(int albumId, int trackId) async {
    final key = albumId > 0 ? albumId : -trackId;
    if (_localAlbumArtCache.containsKey(key)) {
      return _localAlbumArtCache[key];
    }
    try {
      final bytes = await _systemChannel.invokeMethod<Uint8List>(
        'getLocalAlbumArt',
        {'albumId': albumId, 'trackId': trackId},
      );
      if (_localAlbumArtCache.length >= 120) {
        _localAlbumArtCache.remove(_localAlbumArtCache.keys.first);
      }
      _localAlbumArtCache[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> playLocalTrack(
    int trackId, {
    List<int>? queueIds,
  }) async {
    try {
      return await _systemChannel.invokeMethod<bool>('playLocalTrack', {
            'trackId': trackId,
            if (queueIds != null) 'queueIds': queueIds,
          }) ??
          false;
    } catch (e) {
      debugPrint('Error playing local track: $e');
      return false;
    }
  }

  static Future<bool> queueLocalTrackNext(int trackId) async {
    try {
      return await _systemChannel.invokeMethod<bool>('queueLocalTrackNext', {
            'trackId': trackId,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> shareLocalTrack(String contentUri, String title) async {
    try {
      return await _systemChannel.invokeMethod<bool>('shareLocalTrack', {
            'contentUri': contentUri,
            'title': title,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteLocalTrack(int trackId, String contentUri) async {
    try {
      final deleted =
          await _systemChannel.invokeMethod<bool>('deleteLocalTrack', {
            'trackId': trackId,
            'contentUri': contentUri,
          }) ??
          false;
      if (deleted) {
        final updated = localTracksNotifier.value
            .where((t) => t.id != trackId)
            .toList(growable: false);
        localTracksNotifier.value = updated;
      }
      return deleted;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> pickWallpaperImage() async {
    return _systemChannel.invokeMethod<Uint8List>('pickWallpaperImage');
  }

  static Future<void> openAccessibilitySettings() async {
    await _systemChannel.invokeMethod('openAccessibilitySettings');
  }

  static Future<double?> getDeviceTotalMemoryGb() async {
    final bytes = await _systemChannel.invokeMethod<int>(
      'getDeviceTotalMemoryBytes',
    );
    return bytes == null ? null : bytes / (1024 * 1024 * 1024);
  }

  static Future<bool> isDefaultLauncher() async {
    try {
      final bool? result = await _systemChannel.invokeMethod(
        'isDefaultLauncher',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> openDefaultLauncherSettings() async {
    try {
      await _systemChannel.invokeMethod('openDefaultLauncherSettings');
    } catch (e) {
      print('Error opening default launcher settings: $e');
    }
  }

  // Widget Actions
  static Future<List<Map<String, dynamic>>> getAllWidgets() async {
    if (_cachedWidgets != null) return _cachedWidgets!;
    try {
      final List<dynamic>? widgets = await _widgetChannel.invokeMethod(
        'getAllWidgets',
      );
      if (widgets != null) {
        _cachedWidgets = widgets
            .map((w) => Map<String, dynamic>.from(w as Map))
            .toList();
        return _cachedWidgets!;
      }
    } catch (e) {
      print('Error getting widgets: $e');
    }
    return [];
  }

  static Future<int> allocateWidgetId() async {
    try {
      final int? id = await _widgetChannel.invokeMethod('allocateWidgetId');
      return id ?? -1;
    } catch (e) {
      print('Error allocating widget ID: $e');
      return -1;
    }
  }

  static Future<bool> bindWidget(
    int appWidgetId,
    String providerPackage,
    String providerClass,
  ) async {
    try {
      final bool? success = await _widgetChannel.invokeMethod('bindWidget', {
        'appWidgetId': appWidgetId,
        'providerPackage': providerPackage,
        'providerClass': providerClass,
      });
      return success ?? false;
    } catch (e) {
      print('Error binding widget: $e');
      return false;
    }
  }

  static Future<void> deleteWidgetId(int appWidgetId) async {
    try {
      await _widgetChannel.invokeMethod('deleteWidgetId', {
        'appWidgetId': appWidgetId,
      });
    } catch (e) {
      print('Error deleting widget ID: $e');
    }
  }

  static Future<Map<String, dynamic>> widgetCapabilities(
    int appWidgetId,
  ) async {
    try {
      final result = await _widgetChannel.invokeMapMethod<String, dynamic>(
        'widgetCapabilities',
        {'appWidgetId': appWidgetId},
      );
      return result ?? const {};
    } catch (e) {
      print('Error checking widget capabilities: $e');
      return const {};
    }
  }

  static Future<bool> configureWidget(int appWidgetId) async {
    try {
      return await _widgetChannel.invokeMethod<bool>('configureWidget', {
            'appWidgetId': appWidgetId,
          }) ??
          false;
    } catch (e) {
      print('Error opening widget configuration: $e');
      return false;
    }
  }

  static Future<bool> updateWidgetSize(
    int appWidgetId, {
    required int minWidthDp,
    required int minHeightDp,
    int? maxWidthDp,
    int? maxHeightDp,
  }) async {
    try {
      return await _widgetChannel.invokeMethod<bool>('updateWidgetSize', {
            'appWidgetId': appWidgetId,
            'minWidthDp': minWidthDp,
            'minHeightDp': minHeightDp,
            'maxWidthDp': maxWidthDp ?? minWidthDp,
            'maxHeightDp': maxHeightDp ?? minHeightDp,
          }) ??
          false;
    } catch (e) {
      debugPrint('Error updating widget size: $e');
      return false;
    }
  }

  static Future<Uint8List?> captureWidgetSnapshot(
    int appWidgetId, {
    int maxSidePx = 320,
  }) async {
    try {
      return await _widgetChannel.invokeMethod<Uint8List>(
        'captureWidgetSnapshot',
        {'appWidgetId': appWidgetId, 'maxSidePx': maxSidePx},
      );
    } catch (_) {
      return null;
    }
  }

  // Notifications Stream
  static Stream<Map<String, int>> get notificationsStream {
    return _notificationChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, int>.from(event);
      }
      return {};
    });
  }
}
