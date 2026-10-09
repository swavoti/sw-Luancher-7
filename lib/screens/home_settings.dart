import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/feed_provider.dart';
import 'package:swavoti/services/lightweight_mode.dart';
import 'package:swavoti/screens/search_settings.dart';
import 'package:swavoti/screens/app_lock_screen.dart';

class HomeSettings extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const HomeSettings({super.key, this.onSettingsChanged});

  @override
  State<HomeSettings> createState() => _HomeSettingsState();
}

class _HomeSettingsState extends State<HomeSettings> {
  bool _notificationDotsEnabled = false;
  bool _isLoading = true;
  String _feedProvider = 'msn';
  bool _showTimeWeather = true;
  int _gridColumns = 4;
  bool _showHiddenApps = false;
  bool _isDefaultLauncher = false;
  bool _frostedGlassEnabled = false;
  bool _lightweightModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDefault = await LauncherService.isDefaultLauncher();
    final frostedGlassEnabled =
        prefs.getBool('frosted_glass_enabled') ?? true;

    if (mounted) {
      setState(() {
        _notificationDotsEnabled =
            prefs.getBool('notification_dots_enabled') ?? false;
        _feedProvider = prefs.getString('feed_provider') ?? 'msn';
        _showTimeWeather = prefs.getBool('show_time_weather') ?? true;
        _gridColumns = prefs.getInt('grid_columns') ?? 4;
        _showHiddenApps = prefs.getBool('show_hidden_apps') ?? false;
        _isDefaultLauncher = isDefault;
        _frostedGlassEnabled = frostedGlassEnabled;
        _lightweightModeEnabled =
            prefs.getBool(LightweightMode.preferenceKey) ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFrostedGlass(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('frosted_glass_enabled', value);
    setState(() => _frostedGlassEnabled = value);
    widget.onSettingsChanged?.call();
  }

  Future<void> _toggleLightweightMode(bool value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value ? 'Turn on Lightweight mode?' : 'Turn it off?'),
        content: Text(
          value
              ? 'We recommend this when Android marks the device as low-RAM or reports 3.5 GiB of RAM or less. '
                    'It reduces decoded-image and app-icon caches, '
                    'loads icons only as needed, skips nonessential startup preloads, and disables wallpaper blur in the app drawer. '
                    'Your saved blur preference is kept and restored when Lightweight mode is off.'
              : 'This restores regular cache limits, startup preloads, nearby-page icon preloading, and your saved wallpaper blur preference.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(value ? 'Enable' : 'Turn off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LightweightMode.preferenceKey, value);
    LightweightMode.apply(value);
    setState(() => _lightweightModeEnabled = value);
    widget.onSettingsChanged?.call();
  }

  Future<void> _toggleNotificationDots(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_dots_enabled', value);
    setState(() => _notificationDotsEnabled = value);
    widget.onSettingsChanged?.call();

    if (value && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Grant Notification Access'),
          content: const Text(
            'To display notification dots on app icons, Go Launcher 7 requires Notification Access. '
            'This permission also lets the optional Now Playing card show playback details and controls. '
            'Please locate Go Launcher 7 in the next screen and turn on the permission.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                LauncherService.openNotificationSettings();
              },
              child: const Text('Grant'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _toggleTimeWeather(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_time_weather', value);
    final savedItems = prefs.getStringList('launcher_items') ?? [];
    if (value) {
      if (!savedItems.any((s) => s.contains('"type":"time_weather_widget"'))) {
        savedItems.add(
          '{"id":"time_weather_default","type":"time_weather_widget","packageName":"","className":null,"appWidgetId":null,"x":0,"y":0,"spanX":4,"spanY":1,"page":0,"label":"Time & Weather"}',
        );
        await prefs.setStringList('launcher_items', savedItems);
      }
    } else {
      savedItems.removeWhere((s) => s.contains('"type":"time_weather_widget"'));
      await prefs.setStringList('launcher_items', savedItems);
    }
    setState(() => _showTimeWeather = value);
  }

  Future<void> _toggleShowHiddenApps(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_hidden_apps', value);
    setState(() => _showHiddenApps = value);
  }

  Future<void> _openGestureFallbackSettings() async {
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gesture fallback'),
        content: const Text(
          'If you enable Go Launcher gesture fallback in Android Accessibility settings, '
          'the service will receive app-window change events (app package only; it does not read screen contents '
          'or send data) and show a small handle over other apps. Tap or swipe up briefly on that handle to request Home, '
          'or swipe up and hold to request Recents. This custom handle is a workaround and does not replace or '
          'intercept Android’s native navigation gestures. You can turn the service off in Accessibility settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (shouldContinue == true) {
      try {
        await LauncherService.openAccessibilitySettings();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Accessibility settings: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Home Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _categoryTile(
                  context,
                  icon: Icons.home_outlined,
                  title: 'Home screen',
                  subtitle: 'Widget, layout, and navigation settings',
                  settings: [
                    SwitchListTile(
                      secondary: const Icon(Icons.access_time_outlined),
                      title: const Text('Show Time & Weather'),
                      subtitle: const Text(
                        'Display time/weather widget on home screen',
                      ),
                      value: _showTimeWeather,
                      onChanged: _toggleTimeWeather,
                    ),
                    ListTile(
                      leading: const Icon(Icons.grid_on_outlined),
                      title: const Text('Workspace Grid Size'),
                      subtitle: Text('$_gridColumns Columns'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GridSizeScreen(
                              currentColumns: _gridColumns,
                            ),
                          ),
                        );
                        _loadSettings();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.gesture_outlined),
                      title: const Text('Gesture fallback'),
                      subtitle: const Text(
                        'Optional Home and Recents handle for navigation issues',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _openGestureFallbackSettings,
                    ),
                  ],
                ),
                _categoryTile(
                  context,
                  icon: Icons.apps_outlined,
                  title: 'Apps & privacy',
                  subtitle: 'App badges, hidden apps, and App Lock',
                  settings: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: const Text('Notification Dots'),
                      subtitle: const Text(
                        'Show badge on app icons for unread notifications',
                      ),
                      value: _notificationDotsEnabled,
                      onChanged: _toggleNotificationDots,
                    ),
                    ListTile(
                      leading: const Icon(Icons.music_note_rounded),
                      title: const Text('Now Playing'),
                      subtitle: const Text(
                        'Requires Notification Access to show playback details and controls',
                      ),
                      onTap: LauncherService.openNotificationSettings,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.visibility_outlined),
                      title: const Text('Show Hidden Apps'),
                      subtitle: const Text(
                        'View apps you have hidden from the drawer',
                      ),
                      value: _showHiddenApps,
                      onChanged: _toggleShowHiddenApps,
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline_rounded),
                      title: const Text('App Lock'),
                      subtitle: const Text(
                        'Require your PIN before opening selected apps',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AppLockScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                _categoryTile(
                  context,
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: 'App drawer and icon styling',
                  settings: [
                    SwitchListTile(
                      secondary: const Icon(Icons.blur_on),
                      title: const Text('Blur Wallpaper Background'),
                      subtitle: const Text(
                        'App drawer shows wallpaper with blur when on; solid colour when off',
                      ),
                      value: _frostedGlassEnabled,
                      onChanged: _toggleFrostedGlass,
                    ),
                    ListTile(
                      leading: const Icon(Icons.apps_outlined),
                      title: const Text('Edit Icon Shape'),
                      subtitle: const Text('Change app icon shape style'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.of(context).pushNamed('/edit_icons');
                      },
                    ),
                  ],
                ),
                _categoryTile(
                  context,
                  icon: Icons.search_rounded,
                  title: 'Search & Discover',
                  subtitle: 'Search bar and news feed providers',
                  settings: [
                    ListTile(
                      leading: const Icon(Icons.search_rounded),
                      title: const Text('Search Bar Settings'),
                      subtitle: const Text(
                        'Configure search widget appearance and browser',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SearchSettingsScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: const Text('Feed Provider'),
                      subtitle: Text(FeedProvider.fromId(_feedProvider).name),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FeedProviderScreen(
                              currentProvider: _feedProvider,
                            ),
                          ),
                        );
                        _loadSettings();
                      },
                    ),
                  ],
                ),
                _categoryTile(
                  context,
                  icon: Icons.tune_rounded,
                  title: 'Performance',
                  subtitle: 'Memory and loading preferences',
                  settings: [
                    SwitchListTile(
                      secondary: const Icon(Icons.memory_rounded),
                      title: const Text('Lightweight mode'),
                      subtitle: const Text(
                        'Reduce image caching and background loading for low-RAM devices',
                      ),
                      value: _lightweightModeEnabled,
                      onChanged: _toggleLightweightMode,
                    ),
                  ],
                ),
                if (!_isDefaultLauncher)
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Set as Default Home App'),
                    subtitle: const Text('Unlock the full launcher experience'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: LauncherService.openDefaultLauncherSettings,
                  ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Go Launcher 7'),
                  subtitle: Text('Version 1.0.0 · co.za.launcher3.swavoti'),
                ),
              ],
            ),
    );
  }

  Widget _categoryTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> settings,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: ListView(children: settings),
          ),
        ),
      ),
    );
  }
}

// ─── Sub-screens ─────────────────────────────────────────────────────────────

class FeedProviderScreen extends StatelessWidget {
  final String currentProvider;

  const FeedProviderScreen({super.key, required this.currentProvider});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed Provider')),
      body: ListView(
        children: FeedProvider.all.map((provider) {
          return ListTile(
            title: Text(provider.name),
            trailing: currentProvider == provider.id
                ? const Icon(Icons.check)
                : null,
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('feed_provider', provider.id);
              if (context.mounted) Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}

class GridSizeScreen extends StatelessWidget {
  final int currentColumns;

  const GridSizeScreen({super.key, required this.currentColumns});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace Grid Size')),
      body: ListView(
        children: [3, 4, 5, 6].map((cols) {
          return ListTile(
            title: Text('$cols Columns'),
            trailing: currentColumns == cols ? const Icon(Icons.check) : null,
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('grid_columns', cols);
              if (context.mounted) Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}
