import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
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
  bool _isDefaultLauncher = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkDefaultLauncher();
  }

  Future<void> _checkDefaultLauncher() async {
    final isDefault = await LauncherService.isDefaultLauncher();
    if (mounted) {
      setState(() {
        _isDefaultLauncher = isDefault;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Home Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildCategoryTile(
                  icon: Icons.home_outlined,
                  title: 'Home screen',
                  subtitle: 'Widget, layout, and grid settings',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HomeScreenSettingsSubscreen(
                        onSettingsChanged: widget.onSettingsChanged,
                      ),
                    ),
                  ),
                ),
                _buildCategoryTile(
                  icon: Icons.apps_rounded,
                  title: 'App Drawer',
                  subtitle: 'Scroll style (Horizontal Swipe vs Vertical A–Z) & visuals',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppDrawerSettingsScreen(
                        onSettingsChanged: widget.onSettingsChanged,
                      ),
                    ),
                  ),
                ),
                _buildCategoryTile(
                  icon: Icons.shield_outlined,
                  title: 'Apps & privacy',
                  subtitle: 'App badges, hidden apps, and App Lock',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppsPrivacySettingsSubscreen(
                        onSettingsChanged: widget.onSettingsChanged,
                      ),
                    ),
                  ),
                ),
                _buildCategoryTile(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: 'Dynamic theming, wallpapers, and icon styling',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppearanceSettingsSubscreen(
                        onSettingsChanged: widget.onSettingsChanged,
                      ),
                    ),
                  ),
                ),
                _buildCategoryTile(
                  icon: Icons.search_rounded,
                  title: 'Search Settings',
                  subtitle: 'Search bar appearance and browser choices',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchSettingsScreen(),
                    ),
                  ),
                ),
                _buildCategoryTile(
                  icon: Icons.tune_rounded,
                  title: 'Performance',
                  subtitle: 'Memory and loading preferences',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PerformanceSettingsSubscreen(
                        onSettingsChanged: widget.onSettingsChanged,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 24),
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

  Widget _buildCategoryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}

// ─── 1. Home Screen Subscreen (Reactive in Real Time) ─────────────────────────

class HomeScreenSettingsSubscreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const HomeScreenSettingsSubscreen({super.key, this.onSettingsChanged});

  @override
  State<HomeScreenSettingsSubscreen> createState() =>
      _HomeScreenSettingsSubscreenState();
}

class _HomeScreenSettingsSubscreenState
    extends State<HomeScreenSettingsSubscreen> {
  bool _showTimeWeather = true;
  int _gridColumns = 4;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showTimeWeather = prefs.getBool('show_time_weather') ?? true;
        _gridColumns = prefs.getInt('grid_columns') ?? 4;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleTimeWeather(bool value) async {
    setState(() => _showTimeWeather = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_time_weather', value);
    final savedItems = prefs.getStringList('launcher_items') ?? [];
    if (value) {
      if (!savedItems.any((s) => s.contains('"type":"time_weather_widget"'))) {
        savedItems.add(
          '{"id":"time_weather_default","type":"time_weather_widget","packageName":"","className":null,"appWidgetId":null,"x":0,"y":0,"spanX":4,"spanY":2,"page":0,"label":"Time & Weather"}',
        );
        await prefs.setStringList('launcher_items', savedItems);
      }
    } else {
      savedItems.removeWhere((s) => s.contains('"type":"time_weather_widget"'));
      await prefs.setStringList('launcher_items', savedItems);
    }
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Home screen'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.access_time_outlined),
                  title: const Text('Show Time & Weather'),
                  subtitle: const Text(
                    'Display double stacked clock & weather widget on home screen',
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
                    _load();
                    widget.onSettingsChanged?.call();
                  },
                ),
              ],
            ),
    );
  }
}

// ─── 2. App Drawer Settings Screen with Live Visual Mockup ───────────────────

class AppDrawerSettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const AppDrawerSettingsScreen({super.key, this.onSettingsChanged});

  @override
  State<AppDrawerSettingsScreen> createState() =>
      _AppDrawerSettingsScreenState();
}

class _AppDrawerSettingsScreenState extends State<AppDrawerSettingsScreen> {
  String _scrollMode = 'horizontal'; // 'horizontal' or 'vertical'
  bool _frostedGlass = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _scrollMode = prefs.getString('drawer_scroll_mode') ?? 'horizontal';
        _frostedGlass = prefs.getBool('frosted_glass_enabled') ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectMode(String mode) async {
    HapticFeedback.selectionClick();
    setState(() => _scrollMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drawer_scroll_mode', mode);
    widget.onSettingsChanged?.call();
  }

  Future<void> _toggleFrostedGlass(bool value) async {
    setState(() => _frostedGlass = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('frosted_glass_enabled', value);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('App Drawer'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Text(
                  'Scroll Layout Style',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap to choose how apps are organized and scrolled in the app drawer.',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Side-by-Side Visual Mockup Cards in Pure Dart
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT: Horizontal Swipe Preview
                    Expanded(
                      child: _buildStyleCard(
                        title: 'Horizontal Swipe',
                        subtitle: 'Swipe left & right (Carousel)',
                        isSelected: _scrollMode == 'horizontal',
                        onTap: () => _selectMode('horizontal'),
                        preview: _buildHorizontalMockup(cs),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // RIGHT: Vertical Scroll Preview
                    Expanded(
                      child: _buildStyleCard(
                        title: 'Vertical Scroll',
                        subtitle: 'Scroll down A–Z index',
                        isSelected: _scrollMode == 'vertical',
                        onTap: () => _selectMode('vertical'),
                        preview: _buildVerticalMockup(cs),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 8),

                Text(
                  'App Drawer Appearance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.blur_on),
                  title: const Text('Blur Wallpaper Background'),
                  subtitle: const Text(
                    'App drawer blurs wallpaper when on; solid color when off',
                  ),
                  value: _frostedGlass,
                  onChanged: _toggleFrostedGlass,
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Edit App Icon Shapes'),
                  subtitle: const Text('Change shapes and icon pack'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).pushNamed('/edit_icons');
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildStyleCard({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required Widget preview,
  }) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.35)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header row with title and check icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // The Live UI Mockup
            preview,
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pure Dart visual mockup: Horizontal Swipe with Carousel & Page Dots
  Widget _buildHorizontalMockup(ColorScheme cs) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Mini search pill
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                Icon(Icons.search, size: 9, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Mini Horizontal Carousel page with side arrows
          Expanded(
            child: Row(
              children: [
                Icon(Icons.chevron_left_rounded, size: 14, color: cs.primary),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    physics: const NeverScrollableScrollPhysics(),
                    children: List.generate(6, (i) {
                      return Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.primary.withValues(alpha: 0.22),
                          ),
                          child: Icon(
                            Icons.apps,
                            size: 10,
                            color: cs.primary,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 14, color: cs.primary),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 3 Page Dots indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 3),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 3),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Pure Dart visual mockup: Vertical Continuous Scroll with A-Z alphabet track
  Widget _buildVerticalMockup(ColorScheme cs) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Mini search pill
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                Icon(Icons.search, size: 9, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Mini vertical list with A-Z alphabet rail
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Letter A
                      Text(
                        'A',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                      Row(
                        children: [
                          _miniCircleIcon(cs),
                          const SizedBox(width: 4),
                          _miniCircleIcon(cs),
                          const SizedBox(width: 4),
                          _miniCircleIcon(cs),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Letter B
                      Text(
                        'B',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                      Row(
                        children: [
                          _miniCircleIcon(cs),
                          const SizedBox(width: 4),
                          _miniCircleIcon(cs),
                          const SizedBox(width: 4),
                          _miniCircleIcon(cs),
                        ],
                      ),
                    ],
                  ),
                ),
                // A-Z Alphabet track
                Container(
                  width: 10,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text('A', style: TextStyle(fontSize: 6, fontWeight: FontWeight.bold, color: cs.primary)),
                      Text('•', style: TextStyle(fontSize: 6, color: cs.onSurfaceVariant)),
                      Text('M', style: TextStyle(fontSize: 6, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                      Text('•', style: TextStyle(fontSize: 6, color: cs.onSurfaceVariant)),
                      Text('Z', style: TextStyle(fontSize: 6, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Scroll down indicator
          Icon(Icons.keyboard_arrow_down, size: 14, color: cs.primary),
        ],
      ),
    );
  }

  Widget _miniCircleIcon(ColorScheme cs) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withValues(alpha: 0.22),
      ),
      child: Icon(Icons.apps, size: 8, color: cs.primary),
    );
  }
}

// ─── 3. Apps & Privacy Subscreen (Reactive in Real Time) ──────────────────────

class AppsPrivacySettingsSubscreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const AppsPrivacySettingsSubscreen({super.key, this.onSettingsChanged});

  @override
  State<AppsPrivacySettingsSubscreen> createState() =>
      _AppsPrivacySettingsSubscreenState();
}

class _AppsPrivacySettingsSubscreenState
    extends State<AppsPrivacySettingsSubscreen> {
  bool _notificationDots = false;
  bool _showHiddenApps = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _notificationDots =
            prefs.getBool('notification_dots_enabled') ?? false;
        _showHiddenApps = prefs.getBool('show_hidden_apps') ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleNotificationDots(bool value) async {
    setState(() => _notificationDots = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_dots_enabled', value);
    widget.onSettingsChanged?.call();

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

  Future<void> _toggleShowHiddenApps(bool value) async {
    setState(() => _showHiddenApps = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_hidden_apps', value);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Apps & privacy'),
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
                  subtitle: const Text(
                    'Show badge on app icons for unread notifications',
                  ),
                  value: _notificationDots,
                  onChanged: _toggleNotificationDots,
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
    );
  }
}

// ─── 4. Appearance Subscreen (Reactive in Real Time) ──────────────────────────

class AppearanceSettingsSubscreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const AppearanceSettingsSubscreen({super.key, this.onSettingsChanged});

  @override
  State<AppearanceSettingsSubscreen> createState() =>
      _AppearanceSettingsSubscreenState();
}

class _AppearanceSettingsSubscreenState
    extends State<AppearanceSettingsSubscreen> {
  bool _dynamicTheming = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dynamicTheming = prefs.getBool('dynamic_theming_enabled') ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleDynamicTheming(bool value) async {
    setState(() => _dynamicTheming = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dynamic_theming_enabled', value);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Appearance'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('Dynamic Theming (Material You)'),
                  subtitle: const Text(
                    'Adapt launcher colors to wallpaper. Pure OLED black when off',
                  ),
                  value: _dynamicTheming,
                  onChanged: _toggleDynamicTheming,
                ),
                ListTile(
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: const Text('Wallpaper & style'),
                  subtitle: const Text('Change wallpaper and color palette'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).pushNamed('/wallpaper');
                  },
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
    );
  }
}

// ─── 5. Performance Subscreen (Reactive in Real Time) ─────────────────────────

class PerformanceSettingsSubscreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const PerformanceSettingsSubscreen({super.key, this.onSettingsChanged});

  @override
  State<PerformanceSettingsSubscreen> createState() =>
      _PerformanceSettingsSubscreenState();
}

class _PerformanceSettingsSubscreenState
    extends State<PerformanceSettingsSubscreen> {
  bool _lightweightMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lightweightMode =
            prefs.getBool(LightweightMode.preferenceKey) ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLightweightMode(bool value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value ? 'Turn on Lightweight mode?' : 'Turn it off?'),
        content: Text(
          value
              ? 'Reduces decoded-image and icon caches for lower memory usage.'
              : 'Restores regular cache limits and startup preloads.',
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

    setState(() => _lightweightMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LightweightMode.preferenceKey, value);
    LightweightMode.apply(value);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Performance'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.memory_rounded),
                  title: const Text('Lightweight mode'),
                  subtitle: const Text(
                    'Reduce image caching and background loading for low-RAM devices',
                  ),
                  value: _lightweightMode,
                  onChanged: _toggleLightweightMode,
                ),
              ],
            ),
    );
  }
}

// ─── Grid Size Screen ────────────────────────────────────────────────────────

class GridSizeScreen extends StatelessWidget {
  final int currentColumns;

  const GridSizeScreen({super.key, required this.currentColumns});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: const Text('Workspace Grid Size'),
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [3, 4, 5, 6].map((cols) {
          final isSelected = cols == currentColumns;
          return ListTile(
            title: Text('$cols Columns'),
            trailing: isSelected
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
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
