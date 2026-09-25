import 'package:flutter/services.dart';
import 'dart:typed_data';

class LauncherService {
  static const _systemChannel = MethodChannel('co.za.launcher3.swavoti/system');
  static const _widgetChannel = MethodChannel(
    'co.za.launcher3.swavoti/widgets',
  );
  static const _notificationChannel = EventChannel(
    'co.za.launcher3.swavoti/notifications',
  );

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

  // System Actions
  static Future<void> uninstallApp(String packageName) async {
    try {
      await _systemChannel.invokeMethod('uninstallApp', {
        'packageName': packageName,
      });
    } catch (e) {
      print('Error uninstalling app: $e');
    }
  }

  static Future<void> startApp(String packageName) async {
    try {
      await _systemChannel.invokeMethod('startApp', {
        'packageName': packageName,
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
