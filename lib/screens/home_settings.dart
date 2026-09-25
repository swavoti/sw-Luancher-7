import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/screens/edit_icons_page.dart';
import 'package:swavoti/screens/search_settings.dart';

class HomeSettings extends StatefulWidget {
  const HomeSettings({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDefault = await LauncherService.isDefaultLauncher();

    if (mounted) {
      setState(() {
        _notificationDotsEnabled =
            prefs.getBool('notification_dots_enabled') ?? false;
        _feedProvider = prefs.getString('feed_provider') ?? 'msn';
        _showTimeWeather = prefs.getBool('show_time_weather') ?? true;
        _gridColumns = prefs.getInt('grid_columns') ?? 4;
        _showHiddenApps = prefs.getBool('show_hidden_apps') ?? false;
        _isDefaultLauncher = isDefault;
        _frostedGlassEnabled = prefs.getBool('frosted_glass_enabled') ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFrostedGlass(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('frosted_glass_enabled', value);
    setState(() => _frostedGlassEnabled = value);
  }

  Future<void> _toggleNotificationDots(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_dots_enabled', value);
    setState(() => _notificationDotsEnabled = value);

    if (value && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Grant Notification Access'),
          content: const Text(
            'To display notification dots on app icons, Go Launcher 7 requires Notification Access. '
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
        savedItems.add('{"id":"time_weather_default","type":"time_weather_widget","packageName":"","className":null,"appWidgetId":null,"x":0,"y":0,"spanX":4,"spanY":1,"page":0,"label":"Time & Weather"}');
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
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Notification Dots'),
                  subtitle: const Text('Show badge on app icons for unread notifications'),
                  value: _notificationDotsEnabled,
                  onChanged: _toggleNotificationDots,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.access_time_outlined),
                  title: const Text('Show Time & Weather'),
                  subtitle: const Text('Display time/weather widget on home screen'),
                  value: _showTimeWeather,
                  onChanged: _toggleTimeWeather,
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded),
                  title: const Text('Search Bar Settings'),
                  subtitle: const Text('Configure search widget appearance and browser'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchSettingsScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Feed Provider'),
                  subtitle: Text(_feedProvider.toUpperCase()),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => FeedProviderScreen(currentProvider: _feedProvider)),
                    );
                    _loadSettings();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.grid_on_outlined),
                  title: const Text('Workspace Grid Size'),
                  subtitle: Text('$_gridColumns Columns'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GridSizeScreen(currentColumns: _gridColumns)),
                    );
                    _loadSettings();
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_outlined),
                  title: const Text('Show Hidden Apps'),
                  subtitle: const Text('View apps you have hidden from the drawer'),
                  value: _showHiddenApps,
                  onChanged: _toggleShowHiddenApps,
                ),
                const Divider(),
                if (!_isDefaultLauncher)
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Set as Default Home App'),
                    subtitle: const Text('Unlock the full launcher experience'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => LauncherService.openDefaultLauncherSettings(),
                  ),
                ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: const Text('Edit Icon Shape'),
                  subtitle: const Text('Change app icon shape style'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EditIconsPage(
                          backgroundWallpaperPath: '',
                        ),
                      ),
                    );
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Experimental', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.blur_on),
                  title: const Text('Blur Wallpaper Background'),
                  subtitle: const Text('App drawer shows wallpaper with blur when on; solid colour when off'),
                  value: _frostedGlassEnabled,
                  onChanged: _toggleFrostedGlass,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Go Launcher 7'),
                  subtitle: const Text('Version 1.0.0 · co.za.launcher3.swavoti'),
                ),
              ],
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
        children: [
          ListTile(
            title: const Text('MSN'),
            trailing: currentProvider == 'msn' ? const Icon(Icons.check) : null,
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('feed_provider', 'msn');
              if (context.mounted) Navigator.pop(context);
            },
          ),
          ListTile(
            title: const Text('Yahoo'),
            trailing: currentProvider == 'yahoo' ? const Icon(Icons.check) : null,
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('feed_provider', 'yahoo');
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
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
