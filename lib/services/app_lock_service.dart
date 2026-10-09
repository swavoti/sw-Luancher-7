import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/screens/app_lock_pin_screen.dart';
import 'package:swavoti/services/launcher_service.dart';

class AppLockService {
  static const _pinSaltKey = 'app_lock.pin_salt';
  static const _pinHashKey = 'app_lock.pin_hash';
  static const _lockedPackagesKey = 'app_lock.locked_packages';
  static const _storage = FlutterSecureStorage();

  static String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<bool> hasPin() async {
    final salt = await _storage.read(key: _pinSaltKey);
    final hash = await _storage.read(key: _pinHashKey);
    return salt != null && hash != null;
  }

  static Future<void> savePin(String pin) async {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    await _storage.write(key: _pinSaltKey, value: salt);
    await _storage.write(key: _pinHashKey, value: _hashPin(pin, salt));
  }

  static Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _pinSaltKey);
    final expectedHash = await _storage.read(key: _pinHashKey);
    if (salt == null || expectedHash == null) return false;
    return _hashPin(pin, salt) == expectedHash;
  }

  static Future<Set<String>> lockedPackages() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_lockedPackagesKey) ?? []).toSet();
  }

  static Future<void> setPackageLocked(String packageName, bool locked) async {
    final preferences = await SharedPreferences.getInstance();
    final packages = preferences.getStringList(_lockedPackagesKey) ?? [];
    if (locked) {
      if (!packages.contains(packageName)) packages.add(packageName);
    } else {
      packages.remove(packageName);
    }
    await preferences.setStringList(_lockedPackagesKey, packages);
  }

  static Future<void> launchApp(
    BuildContext context,
    String packageName, {
    bool splitScreen = false,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final packages = await lockedPackages();
      if (!packages.contains(packageName)) {
        await LauncherService.startApp(packageName, splitScreen: splitScreen);
        return;
      }

      if (!await hasPin()) {
        if (messenger?.mounted != true) return;
        messenger!.showSnackBar(
          const SnackBar(
            content: Text('Set up your App Lock PIN before locking apps.'),
          ),
        );
        return;
      }

      if (!navigator.mounted) return;
      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => AppLockPinScreen(
            mode: AppLockPinMode.verify,
            onVerified: () =>
                LauncherService.startApp(packageName, splitScreen: splitScreen),
          ),
        ),
      );
    } catch (error) {
      if (messenger?.mounted != true) return;
      messenger!.showSnackBar(
        SnackBar(content: Text('Could not check App Lock: $error')),
      );
    }
  }
}
