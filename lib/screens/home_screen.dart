import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/screens/widget_bottomsheet.dart';
import 'package:swavoti/screens/home_settings.dart';
import 'package:swavoti/screens/wallpaper_page.dart';
import 'package:swavoti/screens/discover_news.dart';
import 'package:swavoti/widgets/search_widget.dart';
import 'package:swavoti/widgets/time_weather_widget.dart';
import 'package:swavoti/widgets/icon_shape_clipper.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

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
    folderApps: json['folderApps'] != null ? List<String>.from(json['folderApps']) : null,
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
  String _iconShape = 'Circle';
  final GlobalKey _repaintBoundaryKey = GlobalKey();

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
    LauncherService.preloadWidgets();
    _loadItemsSync();
    _loadSettingsSync();
    _workspaceController = PageController(initialPage: 0);
    _workspaceController.addListener(_onWorkspaceScroll);
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
                final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                // Discover slides in from left, home slides out to right — feels like same continuous page
                return SlideTransition(
                  position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(curve),
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
    if (mounted) {
      setState(() {
        _showTimeWeather = prefs.getBool('show_time_weather') ?? true;
        _iconShape = prefs.getString('icon_shape') ?? 'Circle';
        _loadItemsFromPrefs(prefs);
      });
    }
  }

  void _loadItemsFromPrefs(SharedPreferences prefs) {
    final data = prefs.getStringList('launcher_items') ?? [];
    final loadedItems = data
        .map((item) => LauncherItem.fromJson(jsonDecode(item)))
        .toList();

    if (!loadedItems.any((i) => i.page == -1)) {
      _applyDefaultWallpaper();
      
      // Dock
      final dock = ['com.google.android.dialer','com.google.android.apps.messaging','com.android.chrome','com.google.android.camera'];
      for (int i = 0; i < 4; i++) {
        loadedItems.add(LauncherItem(id: 'dock_$i', type: 'app', packageName: dock[i], label: 'App', x: i, y: 0, page: -1));
      }

      // Page 0: Time/Weather + Search + 8 apps
      if (prefs.getBool('show_time_weather') ?? true) {
        loadedItems.add(LauncherItem(id: 'time_weather_default', type: 'time_weather_widget', packageName: '', label: 'Time & Weather', x: 0, y: 0, spanX: 4, spanY: 1, page: 0));
      }
      loadedItems.add(LauncherItem(id: 'search_default', type: 'search_widget', packageName: '', label: 'Search', x: 0, y: 4, spanX: 4, spanY: 1, page: 0));
      final page0Apps = ['com.google.android.gm','com.google.android.apps.maps','com.google.android.youtube','com.google.android.apps.photos','com.google.android.music','com.spotify.music','com.whatsapp','com.facebook.katana'];
      for (int i = 0; i < page0Apps.length; i++) {
        loadedItems.add(LauncherItem(id: 'p0_app_$i', type: 'app', packageName: page0Apps[i], label: 'App', x: i % 4, y: 1 + (i ~/ 4), page: 0));
      }

      // Page 1: 12 apps
      final page1Apps = ['com.netflix.mediaclient','com.instagram.android','com.twitter.android','com.snapchat.android','com.linkedin.android','com.amazon.mShop.android.shopping','com.paypal.android.p2pmobile','com.ubercab','com.google.android.keep','com.google.android.calendar','com.google.android.apps.docs','com.google.android.apps.drive'];
      for (int i = 0; i < page1Apps.length; i++) {
        loadedItems.add(LauncherItem(id: 'p1_app_$i', type: 'app', packageName: page1Apps[i], label: 'App', x: i % 4, y: i ~/ 4, page: 1));
      }

      // Page 2: 12 apps
      final page2Apps = ['com.google.android.apps.fitness','com.google.android.apps.walletnfcrel','com.android.settings','com.android.calculator2','com.android.vending','com.google.android.apps.translate','com.shazam.android','com.soundcloud.android','com.duolingo','com.google.android.apps.classroom','com.microsoft.teams','com.slack'];
      for (int i = 0; i < page2Apps.length; i++) {
        loadedItems.add(LauncherItem(id: 'p2_app_$i', type: 'app', packageName: page2Apps[i], label: 'App', x: i % 4, y: i ~/ 4, page: 2));
      }
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

  void _showWorkspaceMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final pageCtrl = PageController(
          viewportFraction: 0.85,
          initialPage: _currentWorkspacePage,
        );
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              color: Colors.transparent,
              padding: const EdgeInsets.only(top: 24, bottom: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Workspace overview cards
                  SizedBox(
                    height: 220,
                    child: PageView.builder(
                      controller: pageCtrl,
                      itemCount: _totalPages,
                      itemBuilder: (ctx2, pageIndex) {
                        final pageItems = _items.where((i) => i.page == pageIndex).toList();
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _workspaceController.jumpToPage(pageIndex);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _currentWorkspacePage == pageIndex
                                    ? cs.primary
                                    : cs.outlineVariant,
                                width: _currentWorkspacePage == pageIndex ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(19),
                              child: Stack(
                                children: [
                                  // Grid dots representing app positions
                                  for (final item in pageItems)
                                    if (item.type == 'app' || item.type == 'folder')
                                      Positioned(
                                        left: (item.x / _columns) * double.infinity,
                                        top: (item.y / _rows) * double.infinity,
                                        child: FractionallySizedBox(
                                          widthFactor: 1 / _columns,
                                          heightFactor: 1 / _rows,
                                          child: Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: cs.primary.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  // Page number label
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(
                                        '${pageIndex + 1}',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildMenuButton(icon: Icons.wallpaper, label: 'Wallpaper', onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const WallpaperPage(homeScreenScreenshot: null)));
                        }),
                        _buildMenuButton(icon: Icons.widgets, label: 'Widgets', onTap: () {
                          Navigator.pop(context);
                          _openWidgetsSheet();
                        }),
                        _buildMenuButton(icon: Icons.settings, label: 'Settings', onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeSettings()))
                            .then((_) { widget.onSettingsChanged(); _reloadSettings(); });
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

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
            Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface), textAlign: TextAlign.center),
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

  void _addNewItem(LauncherItem item) {
    setState(() {
      _items.add(item);
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

  void addWidgetToWorkspace(Map<String, dynamic> widgetData, int widgetId) {
    final spanX = 4;
    final spanY = 2;

    for (int y = 0; y <= _rows - spanY; y++) {
      for (int x = 0; x <= _columns - spanX; x++) {
        bool isOccupied = false;
        for (final item in _items) {
          if (item.page == _currentWorkspacePage) {
            if (x < item.x + item.spanX &&
                x + spanX > item.x &&
                y < item.y + item.spanY &&
                y + spanY > item.y) {
              isOccupied = true;
              break;
            }
          }
        }

        if (!isOccupied) {
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
              page: _currentWorkspacePage,
              label: widgetData['label'],
            ),
          );
          return;
        }
      }
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

    return GestureDetector(
      onLongPress: _showWorkspaceMenu,
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
                        physics: const ClampingScrollPhysics(),
                        controller: _workspaceController,
                        itemCount: _totalPages,
                        onPageChanged: (index) {
                          setState(() => _currentWorkspacePage = index);
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
                                      onWillAcceptWithDetails: (details) =>
                                          true,
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
                                          final itemId = data['id'] as String;
                                          setState(() {
                                            final item = _items.firstWhere(
                                              (i) => i.id == itemId,
                                            );
                                            // Check if there's already an item at target position
                                            final existingIdx = _items.indexWhere(
                                              (i) => i.id != itemId &&
                                                  i.page == pageIndex &&
                                                  i.x == targetX &&
                                                  i.y == targetY,
                                            );
                                            if (existingIdx != -1) {
                                              final target = _items[existingIdx];
                                              if (target.type == 'app' && item.type == 'app') {
                                                target.type = 'folder';
                                                target.label = 'Folder';
                                                target.folderApps = [target.packageName, item.packageName];
                                                _items.remove(item);
                                              } else if (target.type == 'folder' && item.type == 'app') {
                                                target.folderApps ??= [];
                                                if (!target.folderApps!.contains(item.packageName)) {
                                                  target.folderApps!.add(item.packageName);
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
                                          });
                                          _saveItems();
                                        } else if (data['type'] == 'app') {
                                          final existingIdx = _items.indexWhere(
                                            (i) => i.page == pageIndex &&
                                                i.x == targetX &&
                                                i.y == targetY,
                                          );
                                          setState(() {
                                            if (existingIdx != -1) {
                                              final target = _items[existingIdx];
                                              if (target.type == 'app') {
                                                target.type = 'folder';
                                                target.label = 'Folder';
                                                target.folderApps = [target.packageName, data['packageName']];
                                                _saveItems();
                                              } else if (target.type == 'folder') {
                                                target.folderApps ??= [];
                                                if (!target.folderApps!.contains(data['packageName'])) {
                                                  target.folderApps!.add(data['packageName']);
                                                }
                                                _saveItems();
                                              }
                                            } else {
                                              _addNewItem(
                                                LauncherItem(
                                                  id: DateTime.now()
                                                      .millisecondsSinceEpoch
                                                      .toString(),
                                                  type: 'app',
                                                  packageName: data['packageName'],
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
                                                  _addNewItem(
                                                    LauncherItem(
                                                      id: DateTime.now()
                                                          .millisecondsSinceEpoch
                                                          .toString(),
                                                      type: 'widget',
                                                      packageName:
                                                          data['providerPackage'],
                                                      className:
                                                          data['providerClass'],
                                                      appWidgetId: id,
                                                      x: targetX,
                                                      y: targetY,
                                                      spanX: 4,
                                                      spanY: 2,
                                                      page: pageIndex,
                                                      label: data['label'],
                                                    ),
                                                  );
                                                }
                                              });
                                            }
                                          });
                                        }
                                      },
                                      builder: (context, candidateData, _) {
                                        return Container(
                                          margin: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: candidateData.isNotEmpty
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withOpacity(0.5)
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                            borderRadius: BorderRadius.circular(
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
                                  child:
                                      LongPressDraggable<Map<String, dynamic>>(
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
                                          child: SizedBox(
                                            width: item.spanX * cellWidth,
                                            height: item.spanY * cellHeight,
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
                                          onLongPress: () =>
                                              _showItemContextMenu(item),
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
                                            ? Colors.white.withOpacity(0.2)
                                            : Colors.transparent,
                                      );
                                    },
                                  ),
                                ),

                              // Edge drag next page
                              if (_isDragging && pageIndex < _totalPages - 1)
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
                                            ? Colors.white.withOpacity(0.2)
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
                              pageBuilder: (_, __, ___) => const DiscoverNewsPage(),
                              transitionsBuilder: (_, animation, __, child) => SlideTransition(
                                position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
                                    .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                child: child,
                              ),
                              transitionDuration: const Duration(milliseconds: 320),
                              reverseTransitionDuration: const Duration(milliseconds: 280),
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
                      border: Border.all(color: Colors.white60, width: 1.5),
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
                  final dockItems = _items.where((i) => i.page == -1).toList();

                  return Stack(
                    children: [
                      for (int x = 0; x < 4; x++)
                        Positioned(
                          left: x * cellWidth,
                          top: 0,
                          width: cellWidth,
                          height: 90,
                          child: DragTarget<Map<String, dynamic>>(
                            onWillAcceptWithDetails: (details) => true,
                            onAcceptWithDetails: (details) {
                              final data = details.data;
                              if (data['id'] != null) {
                                setState(() {
                                  final item = _items.firstWhere(
                                    (i) => i.id == data['id'],
                                  );
                                  item.x = x;
                                  item.y = 0;
                                  item.page = -1;
                                });
                                _saveItems();
                              } else if (data['type'] == 'app') {
                                _addNewItem(
                                  LauncherItem(
                                    id: DateTime.now().millisecondsSinceEpoch
                                        .toString(),
                                    type: 'app',
                                    packageName: data['packageName'],
                                    label: data['label'],
                                    x: x,
                                    y: 0,
                                    page: -1,
                                  ),
                                );
                              }
                            },
                            builder: (context, candidateData, rejectedData) {
                              return Container(
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: candidateData.isNotEmpty
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primary.withOpacity(0.5)
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
                          child: LongPressDraggable<Map<String, dynamic>>(
                            data: item.toJson(),
                            delay: const Duration(milliseconds: 150),
                            onDragStarted: () {
                              setState(() => _isDragging = true);
                              if (item.type == 'app') {
                                widget.onDragStarted?.call(item.packageName);
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
                                child: _buildItemContent(item, cellWidth, 90),
                              ),
                            ),
                            childWhenDragging: const SizedBox.shrink(),
                            child: GestureDetector(
                              onTap: () =>
                                  LauncherService.startApp(item.packageName),
                              onLongPress: () => _showItemContextMenu(item),
                              child: _buildItemContent(item, cellWidth, 90),
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
    );
  }

  Widget _buildItemContent(
    LauncherItem item,
    double cellWidth,
    double cellHeight, {
    bool isFeedback = false,
  }) {
    if (item.type == 'widget' && item.appWidgetId != null) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _WidgetWrapper(appWidgetId: item.appWidgetId!),
        ),
      );
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
                backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: (item.folderApps ?? []).map((pkg) {
                          final cachedApp = widget.appCache[pkg];
                          Widget buildApp(AppInfo app) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                LauncherService.startApp(pkg);
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconShapeClipper(
                                    shape: _iconShape,
                                    size: 56,
                                    child: app.icon != null
                                        ? Image.memory(app.icon!, width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168)
                                        : const Icon(Icons.android, size: 56),
                                  ),
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
                              ),
                            );
                          }
                          
                          if (cachedApp != null) return buildApp(cachedApp);
                          
                          return FutureBuilder<AppInfo?>(
                            future: _getAppInfo(pkg),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(8),
                child: Builder(
                  builder: (context) {
                    final apps = (item.folderApps ?? []).take(4).toList();
                    if (apps.isEmpty) {
                      return Icon(Icons.folder, color: Theme.of(context).colorScheme.primary);
                    }
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: apps.length,
                      itemBuilder: (context, index) {
                        final pkg = apps[index];
                        final cachedApp = widget.appCache[pkg];

                        Widget buildIcon(AppInfo app) {
                          return IconShapeClipper(
                            shape: _iconShape,
                            size: 18,
                            child: app.icon != null
                                ? Image.memory(app.icon!, width: 18, height: 18, fit: BoxFit.cover, cacheWidth: 54)
                                : const Icon(Icons.android, size: 18),
                          );
                        }

                        if (cachedApp != null) return buildIcon(cachedApp);
                        
                        return FutureBuilder<AppInfo?>(
                          future: _getAppInfo(pkg),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
                            return buildIcon(snapshot.data!);
                          },
                        );
                      },
                    );
                  }
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
                    Shadow(blurRadius: 4.0, color: Colors.black54, offset: Offset(1.0, 1.0)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      Widget buildAppIcon(AppInfo app, int notificationCount) {
        return Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  IconShapeClipper(
                    shape: _iconShape,
                    size: 56,
                    child: app.icon != null
                        ? Image.memory(
                            app.icon!, 
                            width: 56, 
                            height: 56,
                            fit: BoxFit.cover,
                            cacheWidth: 168,
                          )
                        : const Icon(Icons.android, size: 56),
                  ),
                  if (notificationCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$notificationCount',
                          style: const TextStyle(
                            color: Colors.white,
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
        return buildAppIcon(cachedApp, widget.notifications[item.packageName] ?? 0);
      }
      
      return FutureBuilder<AppInfo?>(
        future: _getAppInfo(item.packageName),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data == null) {
            return const SizedBox.shrink();
          }
          return buildAppIcon(snapshot.data!, widget.notifications[item.packageName] ?? 0);
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
                if (item.type == 'widget') ...[
                  ListTile(
                    leading: const Icon(Icons.aspect_ratio),
                    title: const Text('Resize Widget'),
                    onTap: () {
                      Navigator.pop(context);
                      _showResizeDialog(item);
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

  void _showResizeDialog(LauncherItem item) {
    int currentSpanX = item.spanX;
    int currentSpanY = item.spanY;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Resize Widget'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Width:'),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: currentSpanX > 1
                                ? () => setDialogState(() => currentSpanX--)
                                : null,
                          ),
                          Text('$currentSpanX'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: (item.x + currentSpanX) < _columns
                                ? () => setDialogState(() => currentSpanX++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Height:'),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: currentSpanY > 1
                                ? () => setDialogState(() => currentSpanY--)
                                : null,
                          ),
                          Text('$currentSpanY'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: (item.y + currentSpanY) < _rows
                                ? () => setDialogState(() => currentSpanY++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      item.spanX = currentSpanX;
                      item.spanY = currentSpanY;
                    });
                    _saveItems();
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _WidgetWrapper extends StatefulWidget {
  final int appWidgetId;
  const _WidgetWrapper({Key? key, required this.appWidgetId}) : super(key: key);

  @override
  State<_WidgetWrapper> createState() => _WidgetWrapperState();
}

class _WidgetWrapperState extends State<_WidgetWrapper> with AutomaticKeepAliveClientMixin {
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
