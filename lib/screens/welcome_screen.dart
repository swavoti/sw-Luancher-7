import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/lightweight_mode.dart';

class WelcomeScreen extends StatefulWidget {
  final ValueChanged<bool> onFinished;

  const WelcomeScreen({super.key, required this.onFinished});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _repositoryUrl = 'https://github.com/swavoti/sw-Luancher-7';

  int _step = 0;
  bool _isLoadingMemoryInfo = false;
  bool? _lightweightModeEnabled;
  DeviceMemoryInfo? _memoryInfo;
  String? _memoryInfoError;

  Future<void> _loadMemoryInfo() async {
    setState(() {
      _isLoadingMemoryInfo = true;
      _memoryInfoError = null;
    });
    try {
      final info = await LauncherService.getDeviceMemoryInfo();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _memoryInfo = info;
        _lightweightModeEnabled =
            prefs.getBool(LightweightMode.preferenceKey) ?? false;
        _isLoadingMemoryInfo = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _memoryInfoError = 'Could not check device memory: $error';
        _isLoadingMemoryInfo = false;
      });
    }
  }

  Future<void> _showLightweightModeInfo(bool enable) async {
    final info = _memoryInfo;
    final ramLabel = info?.approximateRamLabel ?? 'device RAM';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(enable ? 'Turn on Lightweight mode?' : 'Turn it off?'),
        content: Text(
          enable
              ? 'Android reports $ramLabel${info?.isLowRamDevice == true ? ' and marks this as a low-RAM device' : ''}. '
                    'We recommend this when Android marks a device as low-RAM or reports 3.5 GiB of RAM or less, '
                    'which includes most phones marketed with 3 GB. '
                    'Lightweight mode keeps launcher features available while reducing decoded-image and app-icon caches, '
                    'loading icons only as needed instead of prefetching nearby pages, skipping nonessential startup preloads, '
                    'and turning off the expensive drawer wallpaper blur. Your wallpaper and blur preference are not deleted; '
                    'you can change this setting later in Home Settings.'
              : 'This restores the regular image and icon cache limits, nearby-page icon preloading, startup preloads, '
                    'and your saved wallpaper blur preference.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(enable ? 'Enable' : 'Turn off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LightweightMode.preferenceKey, enable);
    LightweightMode.apply(enable);
    setState(() => _lightweightModeEnabled = enable);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('welcome_completed', true);
    widget.onFinished(prefs.getBool(LightweightMode.preferenceKey) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _step == 0
              ? _buildWelcome(context, colorScheme)
              : _buildSetup(context, colorScheme),
        ),
      ),
    );
  }

  Widget _buildWelcome(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/icon/app_icon.png', width: 112, height: 112),
          const SizedBox(height: 24),
          Text(
            'Welcome to Go Launcher 7',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A customizable Android home screen with no ads. '
            'Free and open source, built by the community.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => LauncherService.openUrlInBrowser(_repositoryUrl),
            icon: const Icon(Icons.code_rounded),
            label: const Text('View source on GitHub'),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                setState(() => _step = 1);
                _loadMemoryInfo();
              },
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetup(BuildContext context, ColorScheme colorScheme) {
    final memoryInfo = _memoryInfo;
    final lowRam = memoryInfo?.shouldRecommendLightweightMode ?? false;
    return Padding(
      key: const ValueKey('setup'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(height: 20),
          Text(
            'A quick setup',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Your launcher is ready. We can tune background work and image caching for this device.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          if (_isLoadingMemoryInfo)
            const LinearProgressIndicator()
          else if (_memoryInfoError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _memoryInfoError!,
                  style: TextStyle(color: colorScheme.error),
                ),
                TextButton(
                  onPressed: _loadMemoryInfo,
                  child: const Text('Try again'),
                ),
              ],
            )
          else if (memoryInfo != null && lowRam)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We detected ${memoryInfo.approximateRamLabel.toLowerCase()}'
                  '${memoryInfo.isLowRamDevice ? ' and Android identifies it as a low-RAM device' : ''}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lightweight mode'),
                  subtitle: const Text(
                    'Recommended to help keep the launcher responsive.',
                  ),
                  value: _lightweightModeEnabled ?? false,
                  onChanged: _showLightweightModeInfo,
                ),
              ],
            )
          else
            Text(
              'This device does not appear to need Lightweight mode. '
              'You can still change performance settings later in Home Settings.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _finish,
              child: const Text('Start using Go Launcher 7'),
            ),
          ),
        ],
      ),
    );
  }
}
