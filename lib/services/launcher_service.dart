import 'package:flutter/services.dart';
import 'dart:typed_data';

class MediaPlaybackInfo {
  final String packageName;
  final String title;
  final String artist;
  final Uint8List? albumArt;
  final Uint8List? appIcon;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;

  const MediaPlaybackInfo({
    required this.packageName,
    required this.title,
    required this.artist,
    required this.albumArt,
    required this.appIcon,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
  });

  factory MediaPlaybackInfo.fromMap(Map<dynamic, dynamic> value) {
    return MediaPlaybackInfo(
      packageName: value['packageName'] as String? ?? '',
      title: value['title'] as String? ?? '',
      artist: value['artist'] as String? ?? '',
      albumArt: value['albumArt'] as Uint8List?,
      appIcon: value['appIcon'] as Uint8List?,
      isPlaying: value['isPlaying'] as bool? ?? false,
      positionMs: value['positionMs'] as int? ?? 0,
      durationMs: value['durationMs'] as int? ?? 0,
    );
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
  }) async {
    try {
      await _systemChannel.invokeMethod('startApp', {
        'packageName': packageName,
        'splitScreen': splitScreen,
      });
    } catch (e) {
      print('Error starting app: $e');
    }
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
