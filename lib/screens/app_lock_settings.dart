import 'package:flutter/material.dart';
import 'package:swavoti/screens/app_lock_pin_screen.dart';
import 'package:swavoti/services/app_lock_service.dart';
import 'package:swavoti/services/launcher_service.dart';

/// Settings page for App Lock: change the PIN and toggle biometric unlock.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  bool _biometricOn = false;
  bool _biometricAvailable = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await AppLockService.isBiometricPreferenceOn();
    final available = await LauncherService.isBiometricAvailable();
    if (!mounted) return;
    setState(() {
      _biometricOn = on && available;
      _biometricAvailable = available;
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeLock() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AppLockPinScreen(
          mode: AppLockPinMode.setup,
          title: 'Change your PIN',
          description: 'Choose a new PIN with 4 or more digits',
        ),
      ),
    );
    if (saved == true && mounted) _toast('PIN changed');
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (!enable) {
      await AppLockService.setBiometricEnabled(false);
      if (mounted) setState(() => _biometricOn = false);
      return;
    }

    if (!await LauncherService.isBiometricAvailable()) {
      if (!mounted) return;
      setState(() => _biometricAvailable = false);
      _toast('No biometrics are set up on this device');
      return;
    }

    // Make the user prove it works before turning it on.
    final verified = await LauncherService.authenticateBiometric(
      title: 'Enable biometric unlock',
      subtitle: 'Verify your biometric to turn this on',
      negativeText: 'Cancel',
    );
    if (!mounted) return;
    if (!verified) {
      _toast('Biometric verification was not completed');
      return;
    }
    await AppLockService.setBiometricEnabled(true);
    if (mounted) setState(() => _biometricOn = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('App Lock settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: const Text('Change lock'),
            subtitle: const Text('Set a new PIN for App Lock'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _changeLock,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('Use biometrics'),
            subtitle: Text(
              _biometricAvailable
                  ? 'Unlock locked apps and App Lock with your fingerprint or face'
                  : 'Not available - set up a fingerprint or face in Android settings',
            ),
            value: _biometricOn,
            onChanged: _loading || !_biometricAvailable ? null : _toggleBiometric,
          ),
        ],
      ),
    );
  }
}

