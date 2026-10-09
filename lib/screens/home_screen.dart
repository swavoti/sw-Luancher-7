import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/app_lock_service.dart';
import 'package:swavoti/screens/widget_bottomsheet.dart';
import 'package:swavoti/screens/discover_news.dart';
import 'package:swavoti/widgets/search_widget.dart';
import 'package:swavoti/widgets/time_weather_widget.dart';
import 'package:swavoti/widgets/icon_shape_clipper.dart';
import 'dart:isolate';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/services/lightweight_mode.dart';

class LauncherItem {
  final String id;
  String type; // 'app' or 'widget' or 'folder'
  String packageName;
  final String? className; // for widgets
  final int? appWidgetId;
  int x;
  int y;
  int spanX;
  int spanY;
  int page;
  String label;
  List<String>? folderApps;

  LauncherItem({
    required this.id,
    required this.type,
    required this.packageName,
    this.className,
    this.appWidgetId,
    required this.x,
    required this.y,
    this.spanX = 1,
    this.spanY = 1,
    this.page = 0,
    required this.label,
    this.folderApps,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'packageName': packageName,
    'className': className,
    'appWidgetId': appWidgetId,
    'x': x,
    'y': y,
    'spanX': spanX,
    'spanY': spanY,
    'page': page,
    'label': label,
    if (folderApps != null) 'folderApps': folderApps,
  };

  factory LauncherItem.fromJson(Map<String, dynamic> json) => LauncherItem(
    id: json['id'],
    type: json['type'],
    packageName: json['packageName'],
    className: json['className'],
    appWidgetId: json['appWidgetId'],
    x: json['x'],
    y: json['y'],
    spanX: json['spanX'] ?? 1,
    spanY: json['spanY'] ?? 1,
    page: json['page'] ?? 0,
    label: json['label'] ?? '',
    folderApps: json['folderApps'] != null
        ? List<String>.from(json['folderApps'])
        : null,
  );
}

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final Map<String, AppInfo> appCache;
  final Map<String, int> notifications;
  final VoidCallback onSettingsChanged;
  final void Function(Map<String, dynamic>)? onAddAppToHomeScreen;
  final void Function(String packageName)? onDragStarted;
  final VoidCallback? onDragEnded;
  final VoidCallback? onDiscoverOpen;
  final VoidCallback? onDiscoverClose;

  const HomeScreen({
    super.key,
    required this.prefs,
    required this.appCache,
    required this.notifications,
    required this.onSettingsChanged,
    this.onAddAppToHomeScreen,
    this.onDragStarted,
    this.onDragEnded,
    this.onDiscoverOpen,
    this.onDiscoverClose,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<LauncherItem> _items = [];
  bool _showTimeWeather = true;
  bool _isDragging = false;
  bool _isNavigatingToDiscover = false;
  bool _isWorkspaceOverviewMode = false;
  String _iconShape = 'Circle';
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  // Split-screen preloaded apps
  List<AppInfo> _allDeviceApps = [];
  bool _isLoadingDeviceApps = false;
  bool _supportsSplitScreen = false;
  String? _editingWidgetId;
  bool _editingWidgetConfigurable = false;
  bool _editingWidgetCanResizeX = false;
  bool _editingWidgetCanResizeY = false;
  int _editingWidgetMinSpanX = 1;
  int _editingWidgetMinSpanY = 1;
  double _resizeDragX = 0;
  double _resizeDragY = 0;
  final Map<String, GlobalKey> _widgetItemKeys = {};

  // Grid Configuration
  final int _columns = 4;
  final int _rows = 5;

  // Always 3 workspace pages minimum
  static const int _minPages = 3;
  int _currentWorkspacePage = 0;
  late final PageController _workspaceController;

  int get _totalPages {
    if (_items.isEmpty) return _minPages;
    int maxPage = _items.fold<int>(
      0,
      (max, item) => item.page > max && item.page >= 0 ? item.page : max,
    );
    // at least _minPages, always one extra blank at end
    return (maxPage + 2).clamp(_minPages, 999);
  }

  @override
  void initState() {
    super.initState();

    // These are pure synchronous reads from SharedPreferences (already in
    // memory) — zero I/O, safe to call in initState.
    _loadItemsSync();
    _loadSettingsSync();
    _workspaceController = PageController(initialPage: 0);
    _workspaceController.addListener(_onWorkspaceScroll);

    // Defer any work that touches platform channels until after the first
    // frame is fully painted. This keeps initState completely idle, which
    // is critical for the gesture snap-back fix — the system must see a
    // completely static layout the moment the window hand-off completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!LightweightMode.isEnabled) {
        LauncherService.preloadWidgets();
        _preloadSplitScreenApps();
      }
      LauncherService.supportsSplitScreen().then((value) {
        if (mounted) setState(() => _supportsSplitScreen = value);
      });
    });
  }

  Future<void> _preloadSplitScreenApps() async {
    if (_isLoadingDeviceApps) return;
    _isLoadingDeviceApps = true;

    try {
      // 1. Silent fast path: retrieve metadata from SQLite cache (names + package names only, < 1MB RAM)
      var apps = await AppDatabaseService.getAppMetadata();

      // 2. If SQLite is empty, query OS launchable apps without icons (withIcon: false)
      if (apps.isEmpty) {
        apps = await InstalledApps.getInstalledApps(
          excludeSystemApps: false,
          excludeNonLaunchableApps: true,
          withIcon: false,
        );
      }

      // Check hidden apps preferences
      final prefs = widget.prefs;
      final hidden = prefs.getStringList('hidden_apps') ?? [];
      final showHidden = prefs.getBool('show_hidden_apps') ?? false;

      // 3. Process, filter and sort inside an isolated background task (Isolate.run).
      // Runs in an isolated memory heap, consuming < 2MB RAM and terminating immediately.
      if (apps.isNotEmpty) {
        final processed = await Isolate.run(
          () => _filterAndSortAppsIsolate(
            apps,
            hidden: showHidden ? const [] : hidden,
          ),
        );

        if (mounted) {
          setState(() {
            _allDeviceApps = processed;
            _isLoadingDeviceApps = false;
          });
        }
      }

      // 4. Background sync with OS to catch any newly installed or uninstalled packages
      AppDatabaseService.syncAppsBackground()
          .then((freshApps) async {
            if (!mounted || freshApps.isEmpty) return;
            final freshProcessed = await Isolate.run(
              () => _filterAndSortAppsIsolate(
                freshApps,
                hidden: showHidden ? const [] : hidden,
              ),
            );
            if (mounted) {
              setState(() {
                _allDeviceApps = freshProcessed;
              });
            }
          })
          .catchError((_) {});
    } catch (e) {
      debugPrint('Error preloading split screen apps: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingDeviceApps = false);
      }
    }
  }

  static List<AppInfo> _filterAndSortAppsIsolate(
    List<AppInfo> list, {
    List<String> hidden = const [],
  }) {
    final hiddenSet = hidden.toSet();
    final filtered = list.where((a) {
      if (a.packageName == 'co.za.launcher3.swavoti') return false;
      if (hiddenSet.contains(a.packageName)) return false;
      return a.isLaunchableApp;
    }).toList();
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return filtered;
  }

  @override
  void dispose() {
    _workspaceController.removeListener(_onWorkspaceScroll);
    _workspaceController.dispose();
    super.dispose();
  }

  /// Called every scroll frame. When the user drags left-to-right past the
  /// beginning of page 0 the PageController offset goes negative — at that
  /// point we push the Discover page. Using the controller offset is far more
  /// reliable than OverscrollNotification with BouncingScrollPhysics on Android.
  void _onWorkspaceScroll() {
    if (!_workspaceController.hasClients) return;

    // Calculate and apply parallax wallpaper offset without rebuilding widget tree
    final page = _workspaceController.page ?? 0.0;
    if (_totalPages > 1) {
      final wallpaperOffset = page / (_totalPages - 1);
      LauncherService.setWallpaperOffset(wallpaperOffset);
    }

    if (_isNavigatingToDiscover) return;
    if (_currentWorkspacePage != 0) return;
    final offset = _workspaceController.offset;
    if (offset < -60) {
      _isNavigatingToDiscover = true;
      widget.onDiscoverOpen?.call();
      // Snap back to position 0 so the bounce doesn't look weird on return
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_workspaceController.hasClients) {
          _workspaceController.jumpTo(0);
        }
      });
      Navigator.of(context)
          .push(
            PageRouteBuilder(
              opaque: true,
              pageBuilder: (_, __, ___) => const DiscoverNewsPage(),
              transitionsBuilder: (_, animation, __, child) {
                final curve = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                );
                // Discover slides in from left, home slides out to right — feels like same continuous page
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(-1, 0),
                    end: Offset.zero,
                  ).animate(curve),
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 320),
              reverseTransitionDuration: const Duration(milliseconds: 280),
            ),
          )
          .then((_) {
            _isNavigatingToDiscover = false;
            widget.onDiscoverClose?.call();
          });
    }
  }

  void _loadSettingsSync() {
    _showTimeWeather = widget.prefs.getBool('show_time_weather') ?? true;
    _iconShape = widget.prefs.getString('icon_shape') ?? 'Circle';
  }

  Future<void> _reloadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Pull out the default-wallpaper check BEFORE setState so we never
    // call async methods inside a setState closure.
    final needsDefaultLayout =
        (prefs.getStringList('launcher_items') ?? []).isEmpty ||
        !(prefs.getStringList('launcher_items') ?? []).any(
          (s) => s.contains('"page":-1'),
        );
    if (needsDefaultLayout) {
      _applyDefaultWallpaper();
    }
    if (!mounted) return;
    setState(() {
      _showTimeWeather = prefs.getBool('show_time_weather') ?? true;
      _iconShape = prefs.getString('icon_shape') ?? 'Circle';
      _loadItemsFromPrefs(prefs);
    });
  }

  Future<void> refreshSettings() => _reloadSettings();

  void _loadItemsFromPrefs(SharedPreferences prefs) {
    final data = prefs.getStringList('launcher_items') ?? [];
    final loadedItems = data
        .map((item) => LauncherItem.fromJson(jsonDecode(item)))
        .toList();

    if (!loadedItems.any((i) => i.page == -1)) {
      // Note: _applyDefaultWallpaper is intentionally NOT called here.
      // It must be called before setState to avoid async-inside-setState crash.

      // Dock
      final dock = [
        'com.google.android.dialer',
        'com.google.android.apps.messaging',
        'com.android.chrome',
        'com.google.android.youtube',
      ];
      for (int i = 0; i < 4; i++) {
        loadedItems.add(
          LauncherItem(
            id: 'dock_$i',
            type: 'app',
            packageName: dock[i],
            label: 'App',
            x: i,
            y: 0,
            page: -1,
          ),
        );
      }

      // Page 0: Time/Weather + Search
      if (prefs.getBool('show_time_weather') ?? true) {
        loadedItems.add(
          LauncherItem(
            id: 'time_weather_default',
            type: 'time_weather_widget',
            packageName: '',
            label: 'Time & Weather',
            x: 0,
            y: 0,
            spanX: 4,
            spanY: 1,
            page: 0,
          ),
        );
      }
      loadedItems.add(
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
      );

      // Page 1: 4 real user apps from the actual device, placed in a clean
      // left-to-right row. Excludes dock apps and system-only packages.
      final dockPackages = {
        'com.google.android.dialer',
        'com.google.android.apps.messaging',
        'com.android.chrome',
        'com.google.android.youtube',
      };
      final userApps = widget.appCache.values
          .where(
            (app) =>
                !dockPackages.contains(app.packageName) &&
                !app.packageName.startsWith('android') &&
                app.packageName != 'co.za.launcher3.swavoti',
          )
          .toList();

      // Pick up to 4, in alphabetical order for consistency
      userApps.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      final page1Pick = userApps.take(4).toList();

      for (int i = 0; i < page1Pick.length; i++) {
        loadedItems.add(
          LauncherItem(
            id: 'p1_app_$i',
            type: 'app',
            packageName: page1Pick[i].packageName,
            label: page1Pick[i].name,
            x: i, // clean left-to-right: 0, 1, 2, 3
            y: 0,
            page: 1,
          ),
        );
      }

      _items = loadedItems;
      _saveItems();
      return;
    }
    _items = loadedItems;
  }

  Future<void> _applyDefaultWallpaper() async {
    try {
      final assetPath = 'assets/wallpapers/default_wallpaper.jpg';
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final success = await LauncherService.setWallpaper(bytes, 1);
      if (success) {
        await widget.prefs.setString('saved_wallpaper_path', assetPath);
      }
    } catch (e) {
      debugPrint('Failed to set default wallpaper: $e');
    }
  }

  void _loadItemsSync() {
    _loadItemsFromPrefs(widget.prefs);
  }

  Future<AppInfo?> _getAppInfo(String packageName) async {
    final cache = widget.appCache;
    if (cache.containsKey(packageName)) return cache[packageName];
    final info = await InstalledApps.getAppInfo(packageName);
    if (info != null) cache[packageName] = info;
    return info;
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _items.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList('launcher_items', data);
  }

  Widget _buildHomeAppIcon(AppInfo app, double size) {
    Widget buildIcon(Uint8List? bytes) {
      return IconShapeClipper(
        shape: _iconShape,
        size: size,
        child: bytes != null && bytes.isNotEmpty
            ? Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                gaplessPlayback: true,
              )
            : Icon(Icons.android, size: size),
      );
    }

    final cachedIcon = AppDatabaseService.getCachedIcon(app.packageName);
    if (cachedIcon != null) return buildIcon(cachedIcon);

    return FutureBuilder<Uint8List?>(
      future: AppDatabaseService.loadIcon(app.packageName),
      builder: (context, snapshot) =>
          buildIcon(snapshot.data ?? app.icon),
    );
  }

  // Replaced bottom sheet with animated scaling overview

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _openWidgetsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WidgetBottomSheet(
        onWidgetSelected: (widgetData) async {
          Navigator.pop(context);
          final id = await LauncherService.allocateWidgetId();
          if (id != -1) {
            final success = await LauncherService.bindWidget(
              id,
              widgetData['providerPackage'],
              widgetData['providerClass'],
            );
            if (success) {
              addWidgetToWorkspace(widgetData, id);
            }
          }
        },
      ),
    );
  }

  void _openSplitScreenPicker() {
    if (_allDeviceApps.isEmpty) {
      _preloadSplitScreenApps();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SplitScreenPickerSheet(
          apps: _allDeviceApps.isNotEmpty
              ? _allDeviceApps
              : widget.appCache.values.toList(),
          iconShape: _iconShape,
          onFetchApps: _preloadSplitScreenApps,
        );
      },
    );
  }

  void _addNewItem(LauncherItem item) {
    setState(() {
      _items.add(item);
    });
    _saveItems();
  }

  LauncherItem? _dockItemAt(int x, {String? excludingId}) {
    for (final item in _items) {
      if (item.page == -1 && item.x == x && item.id != excludingId) {
        return item;
      }
    }
    return null;
  }

  bool _canAcceptDockDrop(Map<String, dynamic> data, int x) {
    if (data['type'] == 'widget') return false;

    LauncherItem? source;
    if (data['id'] is String) {
      for (final item in _items) {
        if (item.id == data['id']) {
          source = item;
          break;
        }
      }
      if (source == null || source.type == 'widget') return false;
    }
    if (source == null && data['type'] != 'app') return false;

    final packageName = source?.type == 'app'
        ? source!.packageName
        : data['packageName'];
    final isApp = source?.type == 'app' || data['type'] == 'app';
    if (isApp && packageName is! String) return false;

    final target = _dockItemAt(x, excludingId: source?.id);
    if (target == null) return true;
    if (!isApp) return false;
    if (target.type == 'app') return target.packageName != packageName;
    if (target.type != 'folder') return false;

    final folderApps = target.folderApps ?? const <String>[];
    return folderApps.length < 8 && !folderApps.contains(packageName);
  }

  void _acceptDockDrop(Map<String, dynamic> data, int x) {
    LauncherItem? source;
    if (data['id'] is String) {
      for (final item in _items) {
        if (item.id == data['id']) {
          source = item;
          break;
        }
      }
    }

    final packageName = source?.type == 'app'
        ? source!.packageName
        : data['packageName'];
    final label = data['label'];
    final target = _dockItemAt(x, excludingId: source?.id);

    setState(() {
      final sourceFolderId = data['source_folder_id'];
      if (sourceFolderId is String) {
        final sourceFolder = _items.where((item) => item.id == sourceFolderId);
        if (sourceFolder.isNotEmpty) {
          final folder = sourceFolder.first;
          folder.folderApps?.remove(packageName);
          if (folder.folderApps?.isEmpty == true) {
            _items.remove(folder);
          }
        }
      }

      if (target != null && packageName is String) {
        if (target.type == 'app') {
          target.type = 'folder';
          target.label = 'Unnamed text';
          target.folderApps = [target.packageName, packageName];
        } else {
          target.folderApps ??= [];
          target.folderApps!.add(packageName);
        }
        if (source != null) _items.remove(source);
      } else if (source != null) {
        source.x = x;
        source.y = 0;
        source.page = -1;
      } else if (data['type'] == 'app' && packageName is String) {
        _items.add(
          LauncherItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: 'app',
            packageName: packageName,
            label: label is String ? label : 'App',
            x: x,
            y: 0,
            page: -1,
          ),
        );
      }
    });
    _saveItems();
  }

  void _removeItem(LauncherItem item) {
    if (item.appWidgetId != null) {
      LauncherService.deleteWidgetId(item.appWidgetId!);
    }
    setState(() {
      _items.remove(item);
    });
    _saveItems();
  }

  void addAppToWorkspace(String packageName, String label) {
    for (int y = 0; y < _rows; y++) {
      for (int x = 0; x < _columns; x++) {
        final isOccupied = _items.any(
          (item) =>
              item.page == _currentWorkspacePage &&
              x >= item.x &&
              x < item.x + item.spanX &&
              y >= item.y &&
              y < item.y + item.spanY,
        );

        if (!isOccupied) {
          _addNewItem(
            LauncherItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: 'app',
              packageName: packageName,
              label: label,
              x: x,
              y: y,
              page: _currentWorkspacePage,
            ),
          );
          return;
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No space left on this workspace page!')),
    );
  }

  void addWidgetToWorkspace(
    Map<String, dynamic> widgetData,
    int widgetId, {
    int? targetX,
    int? targetY,
    int? targetPage,
  }) {
    final spanX = 4;
    final spanY = 2;
    final page = targetPage ?? _currentWorkspacePage;
    final positions = <(int, int)>[];
    if (targetX != null && targetY != null) {
      positions.add((
        targetX.clamp(0, _columns - spanX).toInt(),
        targetY.clamp(0, _rows - spanY).toInt(),
      ));
    }
    for (int y = 0; y <= _rows - spanY; y++) {
      for (int x = 0; x <= _columns - spanX; x++) {
        if (!positions.contains((x, y))) positions.add((x, y));
      }
    }

    for (final (x, y) in positions) {
      final isOccupied = _items.any(
        (item) =>
            item.page == page &&
            x < item.x + item.spanX &&
            x + spanX > item.x &&
            y < item.y + item.spanY &&
            y + spanY > item.y,
      );
      if (isOccupied) continue;

      _addNewItem(
        LauncherItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'widget',
          packageName: widgetData['providerPackage'],
          className: widgetData['providerClass'],
          appWidgetId: widgetId,
          x: x,
          y: y,
          spanX: spanX,
          spanY: spanY,
          page: page,
          label: widgetData['label'],
        ),
      );
      return;
    }

    LauncherService.deleteWidgetId(widgetId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Not enough space for this widget (requires 4x2). Try a blank page!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // The Workspace
        GestureDetector(
          onLongPress: () => setState(() => _isWorkspaceOverviewMode = true),
          onTap: _isWorkspaceOverviewMode
              ? () => setState(() => _isWorkspaceOverviewMode = false)
              : null,
          child: AnimatedScale(
            scale: _isWorkspaceOverviewMode ? 0.75 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: const Alignment(0, -0.5),
            child: RepaintBoundary(
              key: _repaintBoundaryKey,
              child: Container(
                color: Colors.transparent,
                child: Column(
                  children: [
                    SizedBox(height: statusBarHeight + 16),
                    // Workspace Grid
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final cellWidth = constraints.maxWidth / _columns;
                            final cellHeight = constraints.maxHeight / _rows;

                            return PageView.builder(
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              controller: _workspaceController,
                              itemCount: _totalPages,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentWorkspacePage = index;
                                  _editingWidgetId = null;
                                });
                              },
                              itemBuilder: (context, index) {
                                final pageIndex = index;
                                final pageItems = _items
                                    .where((i) => i.page == pageIndex)
                                    .toList();

                                return Stack(
                                  children: [
                                    // Drop targets
                                    for (int y = 0; y < _rows; y++)
                                      for (int x = 0; x < _columns; x++)
                                        Positioned(
                                          left: x * cellWidth,
                                          top: y * cellHeight,
                                          width: cellWidth,
                                          height: cellHeight,
                                          child: DragTarget<Map<String, dynamic>>(
                                            onWillAcceptWithDetails:
                                                (details) => true,
                                            onAcceptWithDetails: (details) {
                                              final data = details.data;
                                              final spanX =
                                                  data['spanX'] as int? ?? 1;
                                              final spanY =
                                                  data['spanY'] as int? ?? 1;
                                              final targetX = x.clamp(
                                                0,
                                                _columns - spanX,
                                              );
                                              final targetY = y.clamp(
                                                0,
                                                _rows - spanY,
                                              );

                                              if (data['id'] != null) {
                                                final itemId =
                                                    data['id'] as String;
                                                final item = _items.firstWhere(
                                                  (i) => i.id == itemId,
                                                );
                                                if (item.type == 'widget') {
                                                  if (_canMoveWidgetTo(
                                                    item,
                                                    targetX,
                                                    targetY,
                                                    pageIndex,
                                                  )) {
                                                    setState(() {
                                                      item.x = targetX;
                                                      item.y = targetY;
                                                      item.page = pageIndex;
                                                      _editingWidgetId = null;
                                                    });
                                                    _saveItems();
                                                  }
                                                  return;
                                                }
                                                setState(() {
                                                  // Check if there's already an item at target position
                                                  final existingIdx = _items
                                                      .indexWhere(
                                                        (i) =>
                                                            i.id != itemId &&
                                                            i.page ==
                                                                pageIndex &&
                                                            i.x == targetX &&
                                                            i.y == targetY,
                                                      );
                                                  if (existingIdx != -1) {
                                                    final target =
                                                        _items[existingIdx];
                                                    if (target.type == 'app' &&
                                                        item.type == 'app') {
                                                      target.type = 'folder';
                                                      target.label =
                                                          'Unnamed text';
                                                      target.folderApps = [
                                                        target.packageName,
                                                        item.packageName,
                                                      ];
                                                      _items.remove(item);
                                                    } else if (target.type ==
                                                            'folder' &&
                                                        item.type == 'app') {
                                                      target.folderApps ??= [];
                                                      if (target
                                                              .folderApps!
                                                              .length <
                                                          8) {
                                                        if (!target.folderApps!
                                                            .contains(
                                                              item.packageName,
                                                            )) {
                                                          target.folderApps!.add(
                                                            item.packageName,
                                                          );
                                                        }
                                                        _items.remove(item);
                                                      } else {
                                                        item.x = targetX;
                                                        item.y = targetY;
                                                        item.page = pageIndex;
                                                      }
                                                    } else {
                                                      item.x = targetX;
                                                      item.y = targetY;
                                                      item.page = pageIndex;
                                                    }
                                                  } else {
                                                    item.x = targetX;
                                                    item.y = targetY;
                                                    item.page = pageIndex;
                                                  }
                                                });
                                                _saveItems();
                                              } else if (data['type'] ==
                                                  'app') {
                                                final existingIdx = _items
                                                    .indexWhere(
                                                      (i) =>
                                                          i.page == pageIndex &&
                                                          i.x == targetX &&
                                                          i.y == targetY,
                                                    );
                                                setState(() {
                                                  if (data['source_folder_id'] !=
                                                      null) {
                                                    final folder = _items
                                                        .firstWhere(
                                                          (i) =>
                                                              i.id ==
                                                              data['source_folder_id'],
                                                        );
                                                    folder.folderApps?.remove(
                                                      data['packageName'],
                                                    );
                                                    if (folder
                                                            .folderApps
                                                            ?.isEmpty ==
                                                        true) {
                                                      _items.remove(folder);
                                                    }
                                                  }

                                                  if (existingIdx != -1) {
                                                    final target =
                                                        _items[existingIdx];
                                                    if (target.type == 'app') {
                                                      target.type = 'folder';
                                                      target.label =
                                                          'Unnamed text';
                                                      target.folderApps = [
                                                        target.packageName,
                                                        data['packageName'],
                                                      ];
                                                      _saveItems();
                                                    } else if (target.type ==
                                                        'folder') {
                                                      target.folderApps ??= [];
                                                      if (target
                                                              .folderApps!
                                                              .length <
                                                          8) {
                                                        if (!target.folderApps!
                                                            .contains(
                                                              data['packageName'],
                                                            )) {
                                                          target.folderApps!.add(
                                                            data['packageName'],
                                                          );
                                                        }
                                                        _saveItems();
                                                      }
                                                    }
                                                  } else {
                                                    _addNewItem(
                                                      LauncherItem(
                                                        id: DateTime.now()
                                                            .millisecondsSinceEpoch
                                                            .toString(),
                                                        type: 'app',
                                                        packageName:
                                                            data['packageName'],
                                                        label: data['label'],
                                                        x: targetX,
                                                        y: targetY,
                                                        page: pageIndex,
                                                      ),
                                                    );
                                                  }
                                                });
                                              } else if (data['type'] ==
                                                  'widget_preview') {
                                                LauncherService.allocateWidgetId().then((
                                                  id,
                                                ) {
                                                  if (id != -1) {
                                                    LauncherService.bindWidget(
                                                      id,
                                                      data['providerPackage'],
                                                      data['providerClass'],
                                                    ).then((success) {
                                                      if (success) {
                                                        addWidgetToWorkspace(
                                                          data,
                                                          id,
                                                          targetX: targetX,
                                                          targetY: targetY,
                                                          targetPage: pageIndex,
                                                        );
                                                      } else {
                                                        LauncherService.deleteWidgetId(
                                                          id,
                                                        );
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          ).showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                'Widget permission was not granted.',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    });
                                                  } else if (mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Unable to allocate widget.',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                });
                                              }
                                            },
                                            builder:
                                                (context, candidateData, _) {
                                                  return Container(
                                                    margin:
                                                        const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color:
                                                            candidateData
                                                                .isNotEmpty
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .primary
                                                                  .withOpacity(
                                                                    0.5,
                                                                  )
                                                            : Colors
                                                                  .transparent,
                                                        width: 2,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                  );
                                                },
                                          ),
                                        ),

                                    // Placed Items
                                    ...pageItems.map((item) {
                                      return Positioned(
                                        left: item.x * cellWidth,
                                        top: item.y * cellHeight,
                                        width: item.spanX * cellWidth,
                                        height: item.spanY * cellHeight,
                                        child: item.type == 'widget'
                                            ? LongPressDraggable<
                                                Map<String, dynamic>
                                              >(
                                                data: item.toJson(),
                                                delay: const Duration(
                                                  milliseconds: 150,
                                                ),
                                                onDragStarted: () {
                                                  setState(() {
                                                    _isDragging = true;
                                                    _editingWidgetId = null;
                                                  });
                                                },
                                                onDragEnd: (_) {
                                                  setState(
                                                    () => _isDragging = false,
                                                  );
                                                  widget.onDragEnded?.call();
                                                },
                                                onDraggableCanceled: (_, __) {
                                                  setState(
                                                    () => _isDragging = false,
                                                  );
                                                  widget.onDragEnded?.call();
                                                },
                                                feedback: Material(
                                                  color: Colors.transparent,
                                                  child: Container(
                                                    width:
                                                        item.spanX * cellWidth,
                                                    height:
                                                        item.spanY * cellHeight,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withOpacity(
                                                                0.24,
                                                              ),
                                                          blurRadius: 16,
                                                        ),
                                                      ],
                                                    ),
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    child: _buildItemContent(
                                                      item,
                                                      cellWidth,
                                                      cellHeight,
                                                      isFeedback: true,
                                                    ),
                                                  ),
                                                ),
                                                childWhenDragging:
                                                    const SizedBox.shrink(),
                                                child: KeyedSubtree(
                                                  key: _widgetItemKeys
                                                      .putIfAbsent(
                                                        item.id,
                                                        () => GlobalKey(),
                                                      ),
                                                  child: GestureDetector(
                                                    onDoubleTap: () =>
                                                        _beginWidgetEdit(item),
                                                    child: _buildItemContent(
                                                      item,
                                                      cellWidth,
                                                      cellHeight,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : LongPressDraggable<
                                                Map<String, dynamic>
                                              >(
                                                data: item.toJson(),
                                                delay: const Duration(
                                                  milliseconds: 150,
                                                ),
                                                onDragStarted: () {
                                                  setState(
                                                    () => _isDragging = true,
                                                  );
                                                  if (item.type == 'app') {
                                                    widget.onDragStarted?.call(
                                                      item.packageName,
                                                    );
                                                  }
                                                },
                                                onDragEnd: (_) {
                                                  setState(
                                                    () => _isDragging = false,
                                                  );
                                                  widget.onDragEnded?.call();
                                                },
                                                onDraggableCanceled: (_, __) {
                                                  setState(
                                                    () => _isDragging = false,
                                                  );
                                                  widget.onDragEnded?.call();
                                                },
                                                feedback: Material(
                                                  color: Colors.transparent,
                                                  child: SizedBox(
                                                    width:
                                                        item.spanX * cellWidth,
                                                    height:
                                                        item.spanY * cellHeight,
                                                    child: _buildItemContent(
                                                      item,
                                                      cellWidth,
                                                      cellHeight,
                                                      isFeedback: true,
                                                    ),
                                                  ),
                                                ),
                                                childWhenDragging:
                                                    const SizedBox.shrink(),
                                                child: GestureDetector(
                                                  onTap: () {
                                                    if (item.type == 'app') {
                                                      AppLockService.launchApp(
                                                        context,
                                                        item.packageName,
                                                      );
                                                    }
                                                  },
                                                  onLongPress: () =>
                                                      _showItemContextMenu(
                                                        item,
                                                      ),
                                                  child: _buildItemContent(
                                                    item,
                                                    cellWidth,
                                                    cellHeight,
                                                  ),
                                                ),
                                              ),
                                      );
                                    }),

                                    // Edge drag prev page
                                    if (_isDragging && pageIndex > 0)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 24,
                                        child: DragTarget<Map<String, dynamic>>(
                                          onWillAcceptWithDetails: (_) {
                                            _workspaceController.previousPage(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              curve: Curves.easeInOut,
                                            );
                                            return false;
                                          },
                                          builder: (context, candidateData, _) {
                                            return Container(
                                              color: candidateData.isNotEmpty
                                                  ? Colors.white.withOpacity(
                                                      0.2,
                                                    )
                                                  : Colors.transparent,
                                            );
                                          },
                                        ),
                                      ),

                                    // Edge drag next page
                                    if (_isDragging &&
                                        pageIndex < _totalPages - 1)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 24,
                                        child: DragTarget<Map<String, dynamic>>(
                                          onWillAcceptWithDetails: (_) {
                                            _workspaceController.nextPage(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              curve: Curves.easeInOut,
                                            );
                                            return false;
                                          },
                                          builder: (context, candidateData, _) {
                                            return Container(
                                              color: candidateData.isNotEmpty
                                                  ? Colors.white.withOpacity(
                                                      0.2,
                                                    )
                                                  : Colors.transparent,
                                            );
                                          },
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // ── Pill Dot Page Indicators ──────────────────────────────
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Discover dot (outlined)
                        GestureDetector(
                          onTap: () {
                            if (!_isNavigatingToDiscover) {
                              _isNavigatingToDiscover = true;
                              Navigator.of(context)
                                  .push(
                                    PageRouteBuilder(
                                      opaque: true,
                                      pageBuilder: (_, __, ___) =>
                                          const DiscoverNewsPage(),
                                      transitionsBuilder:
                                          (
                                            _,
                                            animation,
                                            __,
                                            child,
                                          ) => SlideTransition(
                                            position:
                                                Tween<Offset>(
                                                  begin: const Offset(-1, 0),
                                                  end: Offset.zero,
                                                ).animate(
                                                  CurvedAnimation(
                                                    parent: animation,
                                                    curve: Curves.easeOutCubic,
                                                  ),
                                                ),
                                            child: child,
                                          ),
                                      transitionDuration: const Duration(
                                        milliseconds: 320,
                                      ),
                                      reverseTransitionDuration: const Duration(
                                        milliseconds: 280,
                                      ),
                                    ),
                                  )
                                  .then((_) => _isNavigatingToDiscover = false);
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white60,
                                width: 1.5,
                              ),
                              color: Colors.transparent,
                            ),
                          ),
                        ),
                        // Workspace pill dots
                        ...List.generate(_totalPages, (index) {
                          final isActive = _currentWorkspacePage == index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: isActive ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: isActive
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Persistent Remove Zone — only visible while dragging
                    if (_isDragging)
                      DragTarget<Map<String, dynamic>>(
                        onAcceptWithDetails: (details) {
                          final id = details.data['id'] as String?;
                          if (id != null) {
                            final item = _items.firstWhere((i) => i.id == id);
                            _removeItem(item);
                          }
                          setState(() => _isDragging = false);
                          widget.onDragEnded?.call();
                        },
                        builder: (context, candidateData, rejectedData) {
                          final isHovered = candidateData.isNotEmpty;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(vertical: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isHovered
                                  ? Colors.red.withOpacity(0.85)
                                  : Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: isHovered ? Colors.white : Colors.white70,
                              size: 32,
                            ),
                          );
                        },
                      ),

                    // ── Search Bar Removed (Now a Grid Widget) ─────────────────

                    // App Dock
                    Container(
                      height: 90,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cellWidth = constraints.maxWidth / 4;
                          final dockItems = _items
                              .where((i) => i.page == -1)
                              .toList();

                          return Stack(
                            children: [
                              for (int x = 0; x < 4; x++)
                                Positioned(
                                  left: x * cellWidth,
                                  top: 0,
                                  width: cellWidth,
                                  height: 90,
                                  child: DragTarget<Map<String, dynamic>>(
                                    onWillAcceptWithDetails: (details) =>
                                        _dockItemAt(x) == null &&
                                        _canAcceptDockDrop(details.data, x),
                                    onAcceptWithDetails: (details) {
                                      _acceptDockDrop(details.data, x);
                                    },
                                    builder:
                                        (context, candidateData, rejectedData) {
                                          return Container(
                                            margin: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: candidateData.isNotEmpty
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                          .withOpacity(0.5)
                                                    : Colors.transparent,
                                                width: 2,
                                              ),
                                            ),
                                          );
                                        },
                                  ),
                                ),

                              ...dockItems.map((item) {
                                return Positioned(
                                  left: item.x * cellWidth,
                                  top: 0,
                                  width: cellWidth,
                                  height: 90,
                                  child: DragTarget<Map<String, dynamic>>(
                                    onWillAcceptWithDetails: (details) =>
                                        _canAcceptDockDrop(
                                          details.data,
                                          item.x,
                                        ),
                                    onAcceptWithDetails: (details) =>
                                        _acceptDockDrop(details.data, item.x),
                                    builder: (context, candidateData, _) =>
                                        LongPressDraggable<
                                          Map<String, dynamic>
                                        >(
                                          data: item.toJson(),
                                          delay: const Duration(
                                            milliseconds: 150,
                                          ),
                                          onDragStarted: () {
                                            setState(() => _isDragging = true);
                                            if (item.type == 'app') {
                                              widget.onDragStarted?.call(
                                                item.packageName,
                                              );
                                            }
                                          },
                                          onDragEnd: (_) {
                                            setState(() => _isDragging = false);
                                            widget.onDragEnded?.call();
                                          },
                                          onDraggableCanceled: (_, __) {
                                            setState(() => _isDragging = false);
                                            widget.onDragEnded?.call();
                                          },
                                          feedback: Material(
                                            color: Colors.transparent,
                                            child: Opacity(
                                              opacity: 0.7,
                                              child: _buildItemContent(
                                                item,
                                                cellWidth,
                                                90,
                                              ),
                                            ),
                                          ),
                                          childWhenDragging:
                                              const SizedBox.shrink(),
                                          child: GestureDetector(
                                            onTap: () =>
                                                AppLockService.launchApp(
                                                  context,
                                                  item.packageName,
                                                ),
                                            onLongPress: () =>
                                                _showItemContextMenu(item),
                                            child: _buildItemContent(
                                              item,
                                              cellWidth,
                                              90,
                                            ),
                                          ),
                                        ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Workspace Settings Options Menu
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          bottom: _isWorkspaceOverviewMode ? 48 : -200,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isWorkspaceOverviewMode ? 1.0 : 0.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMenuButton(
                    icon: Icons.wallpaper,
                    label: 'Wallpaper',
                    onTap: () async {
                      setState(() => _isWorkspaceOverviewMode = false);
                      await Navigator.of(context).pushNamed('/wallpaper');
                      if (mounted) widget.onSettingsChanged();
                    },
                  ),
                  if (_supportsSplitScreen)
                    _buildMenuButton(
                      icon: Icons.splitscreen,
                      label: 'Split Screen',
                      onTap: () {
                        setState(() => _isWorkspaceOverviewMode = false);
                        _openSplitScreenPicker();
                      },
                    ),
                  _buildMenuButton(
                    icon: Icons.widgets,
                    label: 'Widgets',
                    onTap: () {
                      setState(() => _isWorkspaceOverviewMode = false);
                      _openWidgetsSheet();
                    },
                  ),
                  _buildMenuButton(
                    icon: Icons.settings,
                    label: 'Settings',
                    onTap: () async {
                      setState(() => _isWorkspaceOverviewMode = false);
                      await Navigator.of(context).pushNamed('/settings');
                      if (!mounted) return;
                      await _reloadSettings();
                      widget.onSettingsChanged();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemContent(
    LauncherItem item,
    double cellWidth,
    double cellHeight, {
    bool isFeedback = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    if (item.type == 'widget' && item.appWidgetId != null) {
      final widgetView = Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _WidgetWrapper(appWidgetId: item.appWidgetId!),
        ),
      );
      if (!isFeedback && _editingWidgetId == item.id) {
        return _buildWidgetEditor(item, widgetView, cellWidth, cellHeight);
      }
      return widgetView;
    } else if (item.type == 'search_widget') {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: SearchWidget(
          onRemove: () {
            setState(() {
              _items.removeWhere((i) => i.id == item.id);
            });
            _saveItems();
          },
        ),
      );
    } else if (item.type == 'time_weather_widget') {
      return TimeWeatherWidget(
        onRemove: () {
          setState(() {
            _items.removeWhere((i) => i.id == item.id);
          });
          _saveItems();
        },
      );
    } else if (item.type == 'folder') {
      return GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) {
              return Dialog(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.85),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatefulBuilder(
                        builder: (context, setStateDialog) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.label,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () {
                                  final controller = TextEditingController(
                                    text: item.label,
                                  );
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Edit Folder Name'),
                                      content: TextField(
                                        controller: controller,
                                        autofocus: true,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            setStateDialog(() {
                                              item.label = controller.text;
                                            });
                                            setState(() {});
                                            _saveItems();
                                            Navigator.pop(context);
                                          },
                                          child: const Text('Save'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: (item.folderApps ?? []).map((pkg) {
                          final cachedApp = widget.appCache[pkg];
                          Widget buildApp(AppInfo app) {
                            final appWidget = Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildHomeAppIcon(app, 56),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    app.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            );

                            return LongPressDraggable<Map<String, dynamic>>(
                              data: {
                                'type': 'app',
                                'packageName': pkg,
                                'source_folder_id': item.id,
                                'label': app.name,
                              },
                              onDragStarted: () {
                                Navigator.pop(context);
                              },
                              feedback: Material(
                                color: Colors.transparent,
                                child: appWidget,
                              ),
                              child: GestureDetector(
                                onTap: () async {
                                  final launch = AppLockService.launchApp(
                                    context,
                                    pkg,
                                  );
                                  Navigator.pop(context);
                                  await launch;
                                },
                                child: appWidget,
                              ),
                            );
                          }

                          if (cachedApp != null) return buildApp(cachedApp);

                          return FutureBuilder<AppInfo?>(
                            future: _getAppInfo(pkg),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data == null)
                                return const SizedBox.shrink();
                              return buildApp(snapshot.data!);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(8),
                child: Builder(
                  builder: (context) {
                    final apps = (item.folderApps ?? []).take(4).toList();
                    if (apps.isEmpty) {
                      return Icon(
                        Icons.folder,
                        color: Theme.of(context).colorScheme.primary,
                      );
                    }
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final pkg = apps[index];
                        final cachedApp = widget.appCache[pkg];

                        Widget buildIcon(AppInfo app) =>
                            _buildHomeAppIcon(app, 18);

                        if (cachedApp != null) return buildIcon(cachedApp);

                        return FutureBuilder<AppInfo?>(
                          future: _getAppInfo(pkg),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data == null)
                              return const SizedBox.shrink();
                            return buildIcon(snapshot.data!);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  shadows: [
                    Shadow(
                      blurRadius: 4.0,
                      color: Colors.black54,
                      offset: Offset(1.0, 1.0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      Widget buildAppIcon(AppInfo app, int notificationCount) {
        final showNotificationDots =
            widget.prefs.getBool('notification_dots_enabled') ?? false;
        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                _buildHomeAppIcon(app, 56),
                  if (showNotificationDots && notificationCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$notificationCount',
                          style: TextStyle(
                            color: colorScheme.onError,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  shadows: [
                    Shadow(
                      blurRadius: 4.0,
                      color: Colors.black54,
                      offset: Offset(1.0, 1.0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      final cachedApp = widget.appCache[item.packageName];
      if (cachedApp != null) {
        return buildAppIcon(
          cachedApp,
          widget.notifications[item.packageName] ?? 0,
        );
      }

      return FutureBuilder<AppInfo?>(
        future: _getAppInfo(item.packageName),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null) {
            return const SizedBox.shrink();
          }
          return buildAppIcon(
            snapshot.data!,
            widget.notifications[item.packageName] ?? 0,
          );
        },
      );
    }
  }

  void _showItemContextMenu(LauncherItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    item.label.isNotEmpty ? item.label : 'Item Actions',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove from Home'),
                  onTap: () {
                    Navigator.pop(context);
                    _removeItem(item);
                  },
                ),
                if (item.type == 'app') ...[
                  ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('Share App'),
                    onTap: () {
                      Navigator.pop(context);
                      LauncherService.shareApp(item.packageName);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('App Info'),
                    onTap: () {
                      Navigator.pop(context);
                      LauncherService.openAppInfo(item.packageName);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_forever,
                      color: Colors.red,
                    ),
                    title: const Text(
                      'Uninstall',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      LauncherService.uninstallApp(item.packageName);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _beginWidgetEdit(LauncherItem item) {
    if (item.appWidgetId == null) return;
    setState(() {
      _editingWidgetId = item.id;
      _editingWidgetConfigurable = false;
      _editingWidgetCanResizeX = false;
      _editingWidgetCanResizeY = false;
      _editingWidgetMinSpanX = item.spanX;
      _editingWidgetMinSpanY = item.spanY;
    });
    LauncherService.widgetCapabilities(item.appWidgetId!).then((capabilities) {
      if (!mounted || _editingWidgetId != item.id) return;
      final canResizeX = capabilities['resizeHorizontal'] == true;
      final canResizeY = capabilities['resizeVertical'] == true;
      final box = _widgetItemKeys[item.id]?.currentContext?.findRenderObject();
      final cellWidth = box is RenderBox && box.hasSize
          ? box.size.width / item.spanX
          : 1.0;
      final cellHeight = box is RenderBox && box.hasSize
          ? box.size.height / item.spanY
          : 1.0;
      final minWidth = capabilities['minResizeWidth'] as int? ?? 0;
      final minHeight = capabilities['minResizeHeight'] as int? ?? 0;
      setState(() {
        _editingWidgetConfigurable = capabilities['configurable'] == true;
        _editingWidgetCanResizeX = canResizeX;
        _editingWidgetCanResizeY = canResizeY;
        _editingWidgetMinSpanX = canResizeX
            ? (minWidth / cellWidth).ceil().clamp(1, _columns).toInt()
            : item.spanX;
        _editingWidgetMinSpanY = canResizeY
            ? (minHeight / cellHeight).ceil().clamp(1, _rows).toInt()
            : item.spanY;
      });
    });
  }

  bool _canResizeWidget(LauncherItem item, int spanX, int spanY) {
    if (spanX < 1 ||
        spanY < 1 ||
        (spanX != item.spanX && spanX < _editingWidgetMinSpanX) ||
        (spanY != item.spanY && spanY < _editingWidgetMinSpanY) ||
        (spanX != item.spanX && !_editingWidgetCanResizeX) ||
        (spanY != item.spanY && !_editingWidgetCanResizeY) ||
        item.x + spanX > _columns ||
        item.y + spanY > _rows) {
      return false;
    }
    return !_items.any(
      (other) =>
          other.id != item.id &&
          other.page == item.page &&
          item.x < other.x + other.spanX &&
          item.x + spanX > other.x &&
          item.y < other.y + other.spanY &&
          item.y + spanY > other.y,
    );
  }

  bool _canMoveWidgetTo(LauncherItem item, int x, int y, int page) {
    if (x < 0 || y < 0 || x + item.spanX > _columns || y + item.spanY > _rows) {
      return false;
    }
    return !_items.any(
      (other) =>
          other.id != item.id &&
          other.page == page &&
          x < other.x + other.spanX &&
          x + item.spanX > other.x &&
          y < other.y + other.spanY &&
          y + item.spanY > other.y,
    );
  }

  void _resizeWidgetByDrag(
    LauncherItem item,
    Offset delta,
    double cellWidth,
    double cellHeight,
  ) {
    _resizeDragX += delta.dx;
    _resizeDragY += delta.dy;
    var changed = false;

    while (_resizeDragX >= cellWidth) {
      if (!_canResizeWidget(item, item.spanX + 1, item.spanY)) {
        _resizeDragX = 0;
        break;
      }
      item.spanX++;
      _resizeDragX -= cellWidth;
      changed = true;
    }
    while (_resizeDragX <= -cellWidth) {
      if (!_canResizeWidget(item, item.spanX - 1, item.spanY)) {
        _resizeDragX = 0;
        break;
      }
      item.spanX--;
      _resizeDragX += cellWidth;
      changed = true;
    }
    while (_resizeDragY >= cellHeight) {
      if (!_canResizeWidget(item, item.spanX, item.spanY + 1)) {
        _resizeDragY = 0;
        break;
      }
      item.spanY++;
      _resizeDragY -= cellHeight;
      changed = true;
    }
    while (_resizeDragY <= -cellHeight) {
      if (!_canResizeWidget(item, item.spanX, item.spanY - 1)) {
        _resizeDragY = 0;
        break;
      }
      item.spanY--;
      _resizeDragY += cellHeight;
      changed = true;
    }

    if (changed && mounted) setState(() {});
  }

  Widget _buildWidgetEditor(
    LauncherItem item,
    Widget child,
    double cellWidth,
    double cellHeight,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        if (_editingWidgetConfigurable)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Widget settings',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: () =>
                    LauncherService.configureWidget(item.appWidgetId!),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          ),
        Positioned(
          top: 8,
          left: 8,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Remove widget',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              onPressed: () {
                setState(() => _editingWidgetId = null);
                _removeItem(item);
              },
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
        if (_editingWidgetCanResizeX || _editingWidgetCanResizeY)
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onPanStart: (_) {
                _resizeDragX = 0;
                _resizeDragY = 0;
              },
              onPanUpdate: (details) => _resizeWidgetByDrag(
                item,
                details.delta,
                cellWidth,
                cellHeight,
              ),
              onPanEnd: (_) => _saveItems(),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomRight: Radius.circular(14),
                  ),
                ),
                child: Icon(
                  Icons.open_in_full_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WidgetWrapper extends StatefulWidget {
  final int appWidgetId;
  const _WidgetWrapper({Key? key, required this.appWidgetId}) : super(key: key);

  @override
  State<_WidgetWrapper> createState() => _WidgetWrapperState();
}

class _WidgetWrapperState extends State<_WidgetWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AndroidView(
      viewType: 'widget_view',
      creationParams: {'appWidgetId': widget.appWidgetId},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

class _SplitScreenPickerSheet extends StatefulWidget {
  final List<AppInfo> apps;
  final String iconShape;
  final Future<void> Function() onFetchApps;

  const _SplitScreenPickerSheet({
    required this.apps,
    required this.iconShape,
    required this.onFetchApps,
  });

  @override
  State<_SplitScreenPickerSheet> createState() =>
      _SplitScreenPickerSheetState();
}

class _SplitScreenPickerSheetState extends State<_SplitScreenPickerSheet> {
  late List<AppInfo> _apps;
  late List<AppInfo> _filteredApps;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _apps = List.from(widget.apps);
    _filteredApps = List.from(_apps);
    _searchController.addListener(_onSearchChanged);

    if (_apps.isEmpty) {
      _isLoading = true;
      InstalledApps.getInstalledApps(
            excludeSystemApps: false,
            excludeNonLaunchableApps: true,
            withIcon: false,
          )
          .then((apps) {
            if (!mounted) return;
            apps.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
            setState(() {
              _apps = apps;
              _filteredApps = List.from(_apps);
              _isLoading = false;
            });
          })
          .catchError((_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          });
    }
  }

  @override
  void didUpdateWidget(covariant _SplitScreenPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.apps.length != oldWidget.apps.length) {
      setState(() {
        _apps = List.from(widget.apps);
        _filter();
      });
    }
  }

  void _onSearchChanged() {
    _filter();
  }

  void _filter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredApps = List.from(_apps);
      } else {
        _filteredApps = _apps
            .where((a) => a.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.35,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Select App for Split Screen',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_filteredApps.isNotEmpty)
                      Text(
                        '${_filteredApps.length} apps',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Search input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search apps...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: _isLoading && _filteredApps.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredApps.isEmpty
                    ? Center(
                        child: Text(
                          'No apps found',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _filteredApps.length,
                        // Strict memory constraint: only decode visible tiles (< 2MB RAM)
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          return _SplitScreenTile(
                            app: app,
                            iconShape: widget.iconShape,
                            onTap: () async {
                              final launch = AppLockService.launchApp(
                                context,
                                app.packageName,
                                splitScreen: true,
                              );
                              Navigator.pop(context);
                              await launch;
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SplitScreenTile extends StatelessWidget {
  final AppInfo app;
  final String iconShape;
  final VoidCallback onTap;

  const _SplitScreenTile({
    required this.app,
    required this.iconShape,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cachedIcon = AppDatabaseService.getCachedIcon(app.packageName);

    Widget buildIconWidget(Uint8List? bytes) {
      return IconShapeClipper(
        shape: iconShape,
        size: 42,
        child: bytes != null && bytes.isNotEmpty
            ? Image.memory(
                bytes,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                cacheWidth: 100, // Strict RAM control: decode max 100px width
                cacheHeight: 100,
              )
            : const Icon(Icons.android, size: 42),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: cachedIcon != null
          ? buildIconWidget(cachedIcon)
          : FutureBuilder<Uint8List?>(
              future: AppDatabaseService.loadIcon(app.packageName),
              builder: (context, snapshot) {
                return buildIconWidget(snapshot.data ?? app.icon);
              },
            ),
      title: Text(
        app.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }
}
