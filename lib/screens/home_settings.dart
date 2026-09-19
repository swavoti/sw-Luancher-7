import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/screens/edit_icons_page.dart';

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
  bool _showSearchWidget = true;
  int _gridColumns = 4;
  bool _showHiddenApps = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if search widget is present in items
    final savedItems = prefs.getStringList('launcher_items') ?? [];
    bool hasSearchWidget = false;
    for (final jsonStr in savedItems) {
      if (jsonStr.contains('"type":"search_widget"')) {
        hasSearchWidget = true;
        break;
      }
    }

    if (mounted) {
      setState(() {
        _notificationDotsEnabled =
            prefs.getBool('notification_dots_enabled') ?? false;
        _feedProvider = prefs.getString('feed_provider') ?? 'msn';
        _showTimeWeather = prefs.getBool('show_time_weather') ?? true;
        _showSearchWidget = hasSearchWidget;
        _gridColumns = prefs.getInt('grid_columns') ?? 4;
        _showHiddenApps = prefs.getBool('show_hidden_apps') ?? false;
        _isLoading = false;
      });
    }
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
    setState(() => _showTimeWeather = value);
  }

  Future<void> _toggleSearchWidget(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final savedItems = prefs.getStringList('launcher_items') ?? [];
    
    if (value) {
      // Add search widget if not present
      if (!savedItems.any((jsonStr) => jsonStr.contains('"type":"search_widget"'))) {
        savedItems.add('{"id":"search_default","type":"search_widget","packageName":"","className":null,"appWidgetId":null,"x":0,"y":0,"spanX":4,"spanY":1,"page":0,"label":"Search"}');
        await prefs.setStringList('launcher_items', savedItems);
      }
    } else {
      // Remove search widget
      savedItems.removeWhere((jsonStr) => jsonStr.contains('"type":"search_widget"'));
      await prefs.setStringList('launcher_items', savedItems);
    }
    
    setState(() => _showSearchWidget = value);
  }

  Future<void> _toggleShowHiddenApps(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_hidden_apps', value);
    setState(() => _showHiddenApps = value);
  }

  void _selectGridColumns() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workspace Grid Size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [3, 4, 5, 6]
              .map(
                (cols) => ListTile(
                  title: Text('$cols Columns'),
                  trailing: _gridColumns == cols
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('grid_columns', cols);
                    setState(() => _gridColumns = cols);
                    if (mounted) Navigator.pop(context);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  void _selectFeedProvider() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Feed Provider'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('MSN'),
              trailing: _feedProvider == 'msn' ? const Icon(Icons.check) : null,
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('feed_provider', 'msn');
                setState(() => _feedProvider = 'msn');
                if (mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Yahoo'),
              trailing: _feedProvider == 'yahoo'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('feed_provider', 'yahoo');
                setState(() => _feedProvider = 'yahoo');
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Home Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Display Group ─────────────────────────────────────────
                _SectionLabel(label: 'Display'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: const Text('Notification Dots'),
                      subtitle: const Text(
                        'Show badge on app icons for unread notifications',
                      ),
                      value: _notificationDotsEnabled,
                      onChanged: _toggleNotificationDots,
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.access_time_outlined),
                      title: const Text('Show Time & Weather'),
                      subtitle: const Text(
                        'Display time/weather widget on home screen',
                      ),
                      value: _showTimeWeather,
                      onChanged: _toggleTimeWeather,
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.search_rounded),
                      title: const Text('Show Search Widget'),
                      subtitle: const Text(
                        'Display search bar widget on home screen',
                      ),
                      value: _showSearchWidget,
                      onChanged: _toggleSearchWidget,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── App Drawer Group ──────────────────────────────────────
                _SectionLabel(label: 'App Drawer'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: const Text('Feed Provider'),
                      subtitle: Text(_feedProvider.toUpperCase()),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _selectFeedProvider,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.grid_on_outlined),
                      title: const Text('Workspace Grid Size'),
                      subtitle: Text('$_gridColumns Columns'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _selectGridColumns,
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.visibility_outlined),
                      title: const Text('Show Hidden Apps'),
                      subtitle: const Text(
                        'View apps you have hidden from the drawer',
                      ),
                      value: _showHiddenApps,
                      onChanged: _toggleShowHiddenApps,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Actions Group ─────────────────────────────────────────
                _SectionLabel(label: 'Actions'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('Set as Default Home App'),
                      subtitle: const Text(
                        'Unlock the full launcher experience',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () =>
                          LauncherService.openDefaultLauncherSettings(),
                    ),
                    const Divider(height: 1, indent: 56),
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
                  ],
                ),

                const SizedBox(height: 20),

                // ── About Group ───────────────────────────────────────────
                _SectionLabel(label: 'About'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Go Launcher 7'),
                      subtitle: const Text(
                        'Version 1.0.0 · co.za.launcher3.swavoti',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }
}
