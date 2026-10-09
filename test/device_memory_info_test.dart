import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/lightweight_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const gibibyte = 1024 * 1024 * 1024;

  test('recommends lightweight mode for approximately 3 GB devices', () {
    final memory = DeviceMemoryInfo(
      totalRamBytes: 3 * gibibyte,
      isLowRamDevice: false,
    );

    expect(memory.shouldRecommendLightweightMode, isTrue);
    expect(memory.approximateRamLabel, 'About 3 GB RAM');
  });

  test('respects Android low-RAM flag even when reported RAM is higher', () {
    final memory = DeviceMemoryInfo(
      totalRamBytes: 6 * gibibyte,
      isLowRamDevice: true,
    );

    expect(memory.shouldRecommendLightweightMode, isTrue);
  });

  test(
    'does not recommend lightweight mode for devices above the threshold',
    () {
      final memory = DeviceMemoryInfo(
        totalRamBytes: 4 * gibibyte,
        isLowRamDevice: false,
      );

      expect(memory.shouldRecommendLightweightMode, isFalse);
    },
  );

  test('lightweight mode reduces Flutter image cache limits', () {
    LightweightMode.apply(true);
    final imageCache = PaintingBinding.instance.imageCache;

    expect(LightweightMode.isEnabled, isTrue);
    expect(imageCache.maximumSize, 100);
    expect(imageCache.maximumSizeBytes, 24 << 20);

    LightweightMode.apply(false);
    expect(LightweightMode.isEnabled, isFalse);
    expect(imageCache.maximumSize, 400);
    expect(imageCache.maximumSizeBytes, 80 << 20);
  });
}
