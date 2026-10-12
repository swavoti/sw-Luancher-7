import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/screens/home_screen.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/weather_service.dart';
import 'package:swavoti/widgets/icon_shape_clipper.dart';
import 'package:swavoti/widgets/weather_icon.dart';

class WallpaperPage extends StatefulWidget {
  final Uint8List? homeScreenScreenshot;
  const WallpaperPage({super.key, this.homeScreenScreenshot});

  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  List<String> _wallpapers = [];
  String _currentPreview = '';
  bool _isLoading = true;
  DateTime _currentTime = DateTime.now();
  Timer? _clockTimer;
  WeatherData? _weatherData;
  List<LauncherItem> _homeItems = [];
  String _iconShape = 'Circle';
  String _searchBarStyle = 'normal';
  Map<String, Uint8List?> _appIcons = {};

  @override
  void initState() {
    super.initState();
    _loadWallpapers();
    _loadHomePreviewData();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWallpapers() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final imagePaths =
          manifest
              .listAssets()
              .where(
                (String key) =>
                    key.startsWith('assets/wallpapers/') &&
                    (key.endsWith('.jpg') ||
                        key.endsWith('.jpeg') ||
                        key.endsWith('.png') ||
                        key.endsWith('.webp')),
              )
              .toList()
            ..sort(); // consistent order

      final prefs = await SharedPreferences.getInstance();
      final savedWallpaper = prefs.getString('saved_wallpaper_path');
      final savedFileExists =
          savedWallpaper != null &&
          !savedWallpaper.startsWith('assets/') &&
          await File(savedWallpaper).exists();
      final preview =
          savedWallpaper != null &&
              (savedWallpaper.startsWith('assets/') || savedFileExists)
          ? savedWallpaper
          : imagePaths.isNotEmpty
          ? imagePaths.first
          : '';

      if (mounted) {
        setState(() {
          _wallpapers = imagePaths;
          _currentPreview = preview;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading wallpapers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadHomePreviewData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shape = prefs.getString('icon_shape') ?? 'Circle';
      final style = prefs.getString('search_bar_style') ?? 'normal';
      final raw = prefs.getStringList('launcher_items') ?? [];

      List<LauncherItem> items = raw
          .map((s) => LauncherItem.fromJson(jsonDecode(s)))
          .toList();

      if (items.isEmpty) {
        final defaultDock = [
          'com.google.android.dialer',
          'com.google.android.apps.messaging',
          'com.android.chrome',
          'com.google.android.youtube',
        ];
        items = [
          for (int i = 0; i < defaultDock.length; i++)
            LauncherItem(
              id: 'dock_$i',
              type: 'app',
              packageName: defaultDock[i],
              label: i == 0
                  ? 'Phone'
                  : i == 1
                  ? 'Messages'
                  : i == 2
                  ? 'Chrome'
                  : 'YouTube',
              x: i,
              y: 0,
              page: -1,
            ),
          LauncherItem(
            id: 'tw_default',
            type: 'time_weather_widget',
            packageName: '',
            label: 'Time & Weather',
            x: 0,
            y: 0,
            spanX: 4,
            spanY: 1,
            page: 0,
          ),
          LauncherItem(
            id: 'search_default',
            type: 'search_widget',
            packageName: '',
            label: 'Search',
            x: 0,
            y: 4,
            spanX: 4,
            spanY: 1,
            page: 0,
          ),
        ];
      }

      final weather = await WeatherService.getCurrentWeather();

      final packages = <String>{};
      for (final item in items) {
        if (item.type == 'app' && item.packageName.isNotEmpty) {
          packages.add(item.packageName);
        } else if (item.type == 'folder' && item.folderApps != null) {
          packages.addAll(item.folderApps!.take(4));
        }
      }

      final iconMap = <String, Uint8List?>{};
      for (final pkg in packages) {
        var icon = AppDatabaseService.getCachedIcon(pkg);
        if (icon == null) {
          try {
            icon = await AppDatabaseService.loadIcon(pkg);
          } catch (_) {}
        }
        iconMap[pkg] = icon;
      }

      if (mounted) {
        setState(() {
          _iconShape = shape;
          _searchBarStyle = style;
          _homeItems = items;
          _weatherData = weather;
          _appIcons = iconMap;
        });
      }
    } catch (e) {
      debugPrint('Error loading home preview data: $e');
    }
  }

  void _showWallpaperGrid() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Wallpaper',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text('Choose from device'),
                  onTap: _pickWallpaperFromDevice,
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8.0),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 9 / 16,
                        ),
                    itemCount: _wallpapers.length,
                    itemBuilder: (context, index) {
                      final path = _wallpapers[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context); // Close grid
                          _showActionSheet(path);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            path,
                            fit: BoxFit.cover,
                            cacheWidth:
                                300, // Important: heavily reduces memory & decoding time
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickWallpaperFromDevice() async {
    Navigator.pop(context);
    try {
      final bytes = await LauncherService.pickWallpaperImage();
      if (bytes == null) return;
      final directory = await getApplicationSupportDirectory();
      final file = File(
        '${directory.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() => _currentPreview = file.path);
      _showActionSheet(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select wallpaper: $error')),
      );
    }
  }

  void _showActionSheet(String assetPath) {
    setState(() {
      _currentPreview = assetPath;
    });

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Set Wallpaper',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Home Screen'),
                onTap: () => _setWallpaper(assetPath, 1),
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Lock Screen'),
                onTap: () => _setWallpaper(assetPath, 2),
              ),
              ListTile(
                leading: const Icon(Icons.phonelink_setup),
                title: const Text('Home and Lock Screens'),
                onTap: () => _setWallpaper(assetPath, 3),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setWallpaper(String assetPath, int type) async {
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Setting wallpaper...')));

    try {
      final Uint8List bytes;
      if (assetPath.startsWith('assets/')) {
        final data = await rootBundle.load(assetPath);
        bytes = data.buffer.asUint8List();
      } else {
        bytes = await File(assetPath).readAsBytes();
      }
      final success = await LauncherService.setWallpaper(bytes, type);

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_wallpaper_path', assetPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Wallpaper set successfully!'
                  : 'Failed to set wallpaper.',
            ),
            backgroundColor: success
                ? Theme.of(context).colorScheme.inverseSurface
                : Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.palette_outlined),
            SizedBox(width: 8),
            Text('Wallpapers & style'),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading wallpapers...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                const SizedBox(height: 24),
                if (_currentPreview.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPreviewScreen('Lock Screen', isLockScreen: true),
                      _buildPreviewScreen('Home Screen', isLockScreen: false),
                    ],
                  )
                else
                  const Expanded(
                    child: Center(
                      child: Text('Choose a wallpaper from your device.'),
                    ),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 28.0),
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.palette_outlined, size: 20),
                        label: const Text('Edit App Icons'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pushNamed('/edit_icons');
                        },
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library_outlined, size: 20),
                        label: const Text('Change Wallpaper'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _showWallpaperGrid,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _formatDateShort(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
  }

  Widget _buildPreviewScreen(String label, {required bool isLockScreen}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            if (_currentPreview.isNotEmpty) {
              _showActionSheet(_currentPreview);
            }
          },
          child: Container(
            width: 154,
            height: 312,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF383838)
                    : const Color(0xFFB0B0B0),
                width: 3.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Wallpaper background
                  if (_currentPreview.isNotEmpty)
                    Image(
                      image: _currentPreview.startsWith('assets/')
                          ? AssetImage(_currentPreview) as ImageProvider
                          : FileImage(File(_currentPreview)),
                      fit: BoxFit.cover,
                    )
                  else
                    Container(color: Colors.black87),

                  // Vignette gradient for text contrast
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(
                            alpha: isLockScreen ? 0.35 : 0.25,
                          ),
                          Colors.transparent,
                          Colors.black.withValues(
                            alpha: isLockScreen ? 0.45 : 0.35,
                          ),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),

                  // Live Mockup Overlay
                  if (isLockScreen)
                    _buildLockScreenOverlay()
                  else
                    _buildHomeScreenOverlay(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Home Screen Mockup Overlay ──────────────────────────────────────────

  Widget _buildHomeScreenOverlay() {
    final page0Items = _homeItems.where((i) => i.page == 0).toList();
    final dockApps = _homeItems
        .where((i) => i.page == -1 && (i.type == 'app' || i.type == 'folder'))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMiniStatusBar(),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellWidth = constraints.maxWidth / 4;
                final cellHeight = constraints.maxHeight / 6;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final item in page0Items)
                      Positioned(
                        left: item.x * cellWidth,
                        top: item.y * cellHeight,
                        width: item.spanX * cellWidth,
                        height: item.spanY * cellHeight,
                        child: _buildMiniWorkspaceItem(item),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          _buildMiniPageDots(),
          const SizedBox(height: 6),
          _buildMiniDock(dockApps),
          const SizedBox(height: 4),
          _buildMiniHomeIndicator(),
        ],
      ),
    );
  }

  Widget _buildMiniWorkspaceItem(LauncherItem item) {
    if (item.type == 'time_weather_widget') {
      return Center(child: _buildMiniTimeWeatherWidget());
    } else if (item.type == 'search_widget') {
      return Center(child: _buildMiniSearchBar());
    } else if (item.type == 'app' || item.type == 'folder') {
      return Center(child: _buildMiniAppItem(item));
    } else if (item.type == 'widget') {
      return Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: Center(
          child: Text(
            item.label.isNotEmpty ? item.label : 'Widget',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 6,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMiniStatusBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${_currentTime.hour}:${_currentTime.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.wifi, size: 7.5, color: Colors.white),
            SizedBox(width: 2),
            Icon(Icons.signal_cellular_alt, size: 7.5, color: Colors.white),
            SizedBox(width: 2),
            Icon(Icons.battery_full, size: 8, color: Colors.white),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniTimeWeatherWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_currentTime.hour}:${_currentTime.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            height: 1.0,
            shadows: [
              Shadow(
                blurRadius: 4,
                color: Colors.black54,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDateShort(_currentTime),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 6.5,
                fontWeight: FontWeight.w600,
                shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
              ),
            ),
            if (_weatherData != null) ...[
              const SizedBox(width: 3),
              WeatherIcon(
                weatherCode: _weatherData!.weatherCode,
                size: 8,
              ),
              const SizedBox(width: 2),
              Text(
                '${_weatherData!.temperature.round()}°',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 6.5,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMiniAppItem(LauncherItem item) {
    return SizedBox(
      width: 28,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.type == 'folder')
            _buildMiniFolderIcon(item, 20)
          else
            _buildMiniAppIcon(
              packageName: item.packageName,
              label: item.label,
              size: 20,
            ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 6,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 2, color: Colors.black87)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAppIcon({
    required String? packageName,
    required String label,
    required double size,
  }) {
    final icon = packageName != null ? _appIcons[packageName] : null;

    Widget iconChild;
    if (icon != null) {
      iconChild = Image.memory(
        icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      final color = _colorForPackage(packageName ?? label);
      final iconData = _fallbackIconForPackage(packageName);
      iconChild = Container(
        width: size,
        height: size,
        color: color,
        child: Center(
          child: iconData != null
              ? Icon(iconData, size: size * 0.55, color: Colors.white)
              : Text(
                  label.isNotEmpty ? label[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.45,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      );
    }

    return IconShapeClipper(
      shape: _iconShape,
      size: size,
      child: iconChild,
    );
  }

  Widget _buildMiniFolderIcon(LauncherItem folder, double size) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 1.5,
        runSpacing: 1.5,
        children: [
          for (int i = 0; i < 4; i++)
            Container(
              width: (size - 8) / 2,
              height: (size - 8) / 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniPageDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 3.5,
          height: 3.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: 0.7,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 7,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 3),
        Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniSearchBar() {
    return Container(
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(
          _searchBarStyle == 'pill' ? 9.0 : 4.0,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 8, color: Colors.white70),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Search',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 6.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Icon(Icons.mic_rounded, size: 8, color: Colors.white70),
        ],
      ),
    );
  }

  Widget _buildMiniDock(List<LauncherItem> dockApps) {
    if (dockApps.isNotEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final item in dockApps.take(4))
            if (item.type == 'folder')
              _buildMiniFolderIcon(item, 20)
            else
              _buildMiniAppIcon(
                packageName: item.packageName,
                label: item.label,
                size: 20,
              ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildMiniAppIcon(
          packageName: 'com.google.android.dialer',
          label: 'Phone',
          size: 20,
        ),
        _buildMiniAppIcon(
          packageName: 'com.google.android.apps.messaging',
          label: 'Messages',
          size: 20,
        ),
        _buildMiniAppIcon(
          packageName: 'com.android.chrome',
          label: 'Chrome',
          size: 20,
        ),
        _buildMiniAppIcon(
          packageName: 'com.google.android.youtube',
          label: 'YouTube',
          size: 20,
        ),
      ],
    );
  }

  Widget _buildMiniHomeIndicator() {
    return Center(
      child: Container(
        width: 28,
        height: 2,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  // ─── Lock Screen Mockup Overlay ──────────────────────────────────────────

  Widget _buildLockScreenOverlay() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLockStatusBar(),
          Expanded(
            child: Center(
              child: _buildAndroidDynamicClock(),
            ),
          ),
          const SizedBox(height: 6),
          _buildMiniHomeIndicator(),
        ],
      ),
    );
  }

  Widget _buildLockStatusBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: const [
        Icon(Icons.battery_full, size: 8.5, color: Colors.white),
      ],
    );
  }

  Widget _buildAndroidDynamicClock() {
    final hour = _currentTime.hour.toString().padLeft(2, '0');
    final minute = _currentTime.minute.toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          hour,
          style: const TextStyle(
            fontSize: 52,
            fontWeight: FontWeight.w900,
            height: 0.85,
            letterSpacing: -2,
            color: Colors.white,
            shadows: [
              Shadow(
                blurRadius: 16,
                color: Colors.black45,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        Text(
          minute,
          style: const TextStyle(
            fontSize: 52,
            fontWeight: FontWeight.w900,
            height: 0.85,
            letterSpacing: -2,
            color: Colors.white,
            shadows: [
              Shadow(
                blurRadius: 16,
                color: Colors.black45,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _colorForPackage(String text) {
    final hash = text.hashCode.abs();
    const colors = [
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFFE53935),
      Color(0xFFFB8C00),
      Color(0xFF8E24AA),
      Color(0xFF00ACC1),
      Color(0xFF3949AB),
      Color(0xFFD81B60),
    ];
    return colors[hash % colors.length];
  }

  IconData? _fallbackIconForPackage(String? pkg) {
    if (pkg == null) return null;
    final lower = pkg.toLowerCase();
    if (lower.contains('dialer') || lower.contains('phone')) {
      return Icons.phone_rounded;
    }
    if (lower.contains('message') || lower.contains('sms')) {
      return Icons.chat_bubble_rounded;
    }
    if (lower.contains('chrome') || lower.contains('browser')) {
      return Icons.language_rounded;
    }
    if (lower.contains('youtube') || lower.contains('video')) {
      return Icons.play_arrow_rounded;
    }
    if (lower.contains('camera')) return Icons.camera_alt_rounded;
    if (lower.contains('photo') || lower.contains('gallery')) {
      return Icons.photo_library_rounded;
    }
    if (lower.contains('setting')) return Icons.settings_rounded;
    if (lower.contains('vending') || lower.contains('store')) {
      return Icons.shopping_bag_rounded;
    }
    return null;
  }
}
