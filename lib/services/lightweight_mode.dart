import 'package:flutter/painting.dart';
import 'package:swavoti/services/app_database_service.dart';

class LightweightMode {
  static const preferenceKey = 'lightweight_mode_enabled';
  static bool isEnabled = false;

  static void apply(bool enabled) {
    final changed = isEnabled != enabled;
    isEnabled = enabled;
    AppDatabaseService.setLightweightMode(enabled);

    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = enabled ? 350 : 800;
    imageCache.maximumSizeBytes = enabled ? 64 << 20 : 180 << 20;

    if (enabled && changed) {
      imageCache.clear();
    }
  }
}
