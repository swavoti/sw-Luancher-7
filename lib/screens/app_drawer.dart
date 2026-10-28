import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/app_lock_service.dart';
import 'package:swavoti/screens/app_lock_screen.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/services/lightweight_mode.dart';
import 'package:swavoti/widgets/icon_shape_clipper.dart';
import 'package:swavoti/screens/home_settings.dart' show AppDrawerSettingsScreen;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:ui';

class AppDrawer extends StatefulWidget {
  final Map<String, int> notifications;
  final VoidCallback onClose;
  final void Function(Map<String, dynamic>)? onAddToHomeScreen;
  final ScrollController scrollController;
  final void Function(String packageName)? onDragStarted;
  final VoidCallback? onDragEnded;
  /// Pre-warmed app list from the home screen. When provided the drawer mounts
  /// instantly without any SQLite cold wait.
  final Map<String, AppInfo>? preloadedAppCache;

  const AppDrawer({
    super.key,
    required this.notifications,
    required this.onClose,
    this.onAddToHomeScreen,
    required this.scrollController,
    this.onDragStarted,
    this.onDragEnded,
    this.preloadedAppCache,
  });

  @override
  State<AppDrawer> createState() => AppDrawerState();
}

class _WorkspaceItemData {
  final String packageName;
  final String label;

  _WorkspaceItemData({required this.packageName, required this.label});

  Map<String, dynamic> toMap() => <String, dynamic>{
    'type': 'app',
    'packageName': packageName,
    'label': label,
  };
}



class AppDrawerState extends State<AppDrawer>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _iconShape = 'Circle';
  bool _notificationDotsEnabled = false;
  bool _frostedGlassEnabled = true;
  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(0);
  final Set<String> _prefetchedPageKeys = {};
  String _iconPack = '';
  int _iconGeneration = 0;
  int _currentPage = 0;
  late final PageController _drawerPageController;
  DateTime? _lastLightweightAppRefresh;
  String _drawerScrollMode = 'horizontal';
  String? _activeAlphabetLetter;

  @override
  void initState() {
    super.initState();
    _drawerPageController = PageController(initialPage: _currentPage);
    // If Workspace passed the pre-warmed app cache, mount instantly —
    // zero SQLite cold wait on the very first open.
    final preloaded = widget.preloadedAppCache;
    if (preloaded != null && preloaded.isNotEmpty) {
      _apps = preloaded.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _filteredApps = List.of(_apps);
      _isLoading = false;
      // Sync in background to catch any newly installed / removed apps
      unawaited(_syncAppsBackground());
    } else {
      _loadApps();
    }
    loadSettings();
    _searchController.addListener(_filterApps);
  }

  Future<void> _syncAppsBackground() async {
    final freshApps = await AppDatabaseService.syncAppsBackground();
    if (!mounted || freshApps.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList('hidden_apps') ?? [];
    final showHidden = prefs.getBool('show_hidden_apps') ?? false;
    final apps = showHidden
        ? freshApps
        : freshApps.where((a) => !hidden.contains(a.packageName)).toList();
    if (_sameApps(_apps, apps)) return;
    if (mounted) {
      setState(() {
        _apps = apps;
        _filteredApps = _filterBySearch(apps);
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageNotifier.dispose();
    _drawerPageController.dispose();
    super.dispose();
  }

  String? _savedWallpaperPath;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _iconShape = prefs.getString('icon_shape') ?? 'Circle';
        _notificationDotsEnabled =
            prefs.getBool('notification_dots_enabled') ?? false;
        final iconPack = prefs.getString('icon_pack') ?? '';
        if (iconPack != _iconPack) {
          _iconPack = iconPack;
          _prefetchedPageKeys.clear();
          _iconGeneration++;
        }
        _frostedGlassEnabled = prefs.getBool('frosted_glass_enabled') ?? true;
        _savedWallpaperPath = prefs.getString('saved_wallpaper_path');
        _drawerScrollMode = prefs.getString('drawer_scroll_mode') ?? 'horizontal';
      });
    }
  }

  void clearIconCache() {
    // Single source of truth is AppDatabaseService
  }

  /// Synchronously prefetch page 0 & 1 icons before drawer navigation animation completes
  void prefetchFirstPage() {
    final apps = _filteredApps.isNotEmpty ? _filteredApps : _apps;
    if (apps.isEmpty) return;
    final firstBatch = apps.take(48).map((a) => a.packageName).toList();
    unawaited(AppDatabaseService.loadIconsBatch(firstBatch));
  }

  Future<void> _loadApps({bool refreshOnDemand = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList('hidden_apps') ?? [];
    final showHidden = prefs.getBool('show_hidden_apps') ?? false;

    List<AppInfo> filterApps(List<AppInfo> apps) {
      if (showHidden) return apps;
      return apps.where((a) => !hidden.contains(a.packageName)).toList();
    }

    // Names from the local cache are displayed immediately. If SQLite is
    // empty or unavailable, get the launchable apps directly from Android.
    List<AppInfo> cachedApps = [];
    try {
      cachedApps = await AppDatabaseService.getAppMetadata().timeout(
        const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('AppDrawer: app cache read timed out or failed: $e');
    }
    var availableApps = filterApps(cachedApps);
    if (availableApps.isEmpty) {
      try {
        final osApps = await InstalledApps.getInstalledApps(
          excludeSystemApps: false,
          excludeNonLaunchableApps: true,
          withIcon: false,
        );
        availableApps = filterApps(osApps);
        if (osApps.isNotEmpty) {
          unawaited(AppDatabaseService.cacheApps(osApps));
        }
      } catch (e) {
        debugPrint('AppDrawer: failed to load installed apps from Android: $e');
      }
    }

    // Instant batch load of the first 48 icons in SQLite BEFORE mounting items!
    // Takes ~3ms and ensures page 0 and 1 render 100% painted on frame 1 without pop-in.
    if (availableApps.isNotEmpty) {
      final earlyBatch = availableApps.take(48).map((a) => a.packageName).toList();
      await AppDatabaseService.loadIconsBatch(earlyBatch);
    }

    if (mounted) {
      setState(() {
        _apps = availableApps;
        _filteredApps = _filterBySearch(availableApps);
        _isLoading = false;
      });
      // Fire prefetch for remaining apps in background so all pages are instant
      if (_filteredApps.length > 48) {
        final remaining = _filteredApps.skip(48).map((a) => a.packageName).toList();
        unawaited(AppDatabaseService.loadIconsBatch(remaining));
      }
    }

    // Refresh cache in the background; the drawer stays usable while SQLite
    // and Android are queried.
    if (!LightweightMode.isEnabled || refreshOnDemand) {
      unawaited(
        AppDatabaseService.syncAppsBackground().then((freshApps) {
          if (!mounted) return;
          if (freshApps.isNotEmpty) {
            final apps = filterApps(freshApps);
            if (_sameApps(_apps, apps)) return;
            setState(() {
              _apps = apps;
              _filteredApps = _filterBySearch(apps);
              _isLoading = false;
            });
            if (_filteredApps.isNotEmpty) {
              _prefetchPage(_filteredApps, 24, 0);
            }
          }
        }),
      );
    }
  }

  Future<void> refreshApps() {
    if (LightweightMode.isEnabled) {
      final lastRefresh = _lastLightweightAppRefresh;
      final now = DateTime.now();
      if (lastRefresh != null &&
          now.difference(lastRefresh) < const Duration(minutes: 5)) {
        return Future<void>.value();
      }
      _lastLightweightAppRefresh = now;
    }
    return _loadApps(refreshOnDemand: true);
  }

  bool _sameApps(List<AppInfo> first, List<AppInfo> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].packageName != second[index].packageName ||
          first[index].name != second[index].name) {
        return false;
      }
    }
    return true;
  }

  List<AppInfo> _filterBySearch(List<AppInfo> apps) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return apps;
    return apps.where((app) => app.name.toLowerCase().contains(query)).toList();
  }

  void _filterApps() {
    setState(() {
      _filteredApps = _filterBySearch(_apps);
    });
  }

  void _prefetchPage(List<AppInfo> apps, int itemsPerPage, int pageIndex) {
    if (pageIndex < 0) return;
    final start = pageIndex * itemsPerPage;
    if (start >= apps.length) return;
    final end = (start + itemsPerPage).clamp(0, apps.length);
    final packages = apps
        .sublist(start, end)
        .map((app) => app.packageName)
        .toList();
    final pageKey = packages.join('\u0000');
    if (!_prefetchedPageKeys.add(pageKey)) return;
    unawaited(AppDatabaseService.loadIconsBatch(packages));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final childContent = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => FocusScope.of(context).unfocus(),
                          borderRadius: BorderRadius.circular(28),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 16),
                                Icon(
                                  Icons.search_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Search apps',
                                      hintStyle: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 15,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () => _searchController.clear(),
                                    padding: EdgeInsets.zero,
                                  ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onSelected: (value) {
                      if (value == 'app_lock') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppLockScreen(),
                          ),
                        );
                      } else if (value == 'edit_icons') {
                        Navigator.pushNamed(context, '/edit_icons');
                      } else if (value == 'drawer_settings') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AppDrawerSettingsScreen(
                              onSettingsChanged: loadSettings,
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (ctx) {
                      final cs = Theme.of(ctx).colorScheme;
                      return [
                        PopupMenuItem(
                          value: 'drawer_settings',
                          child: Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Drawer Settings',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'app_lock',
                          child: Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'App Lock',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'edit_icons',
                          child: Row(
                            children: [
                              Icon(
                                Icons.palette_outlined,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Edit Icons',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_searchController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      LauncherService.openUrlInBrowser(
                        'https://www.google.com/search?q=${Uri.encodeComponent(_searchController.text)}',
                        null,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.travel_explore,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Search "${_searchController.text}" in Web',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const SizedBox.shrink()
              : _filteredApps.isEmpty
              ? const Center(child: Text('No apps found.'))
              : _searchController.text.trim().isNotEmpty
              ? GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.82,
                      ),
                  itemCount: _filteredApps.length,
                  itemBuilder: (context, index) {
                    final app = _filteredApps[index];
                    final notificationCount = _notificationDotsEnabled
                        ? (widget.notifications[app.packageName] ?? 0)
                        : 0;
                    return _AppDrawerItem(
                      key: ValueKey('search_${app.packageName}'),
                      app: app,
                      notificationCount: notificationCount,
                      onCloseDrawer: widget.onClose,
                      iconShape: _iconShape,
                      onDragStarted: widget.onDragStarted,
                      onDragEnded: widget.onDragEnded,
                      iconGeneration: _iconGeneration,
                    );
                  },
                )
              : (_drawerScrollMode == 'vertical'
                  ? _buildVerticalAppDrawer(context)
                  : _buildHorizontalAppDrawer(context)),
        ),
      ],
    );

    return ScrollConfiguration(
      behavior: const StretchScrollBehavior(),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Stack(
          children: [
            if (!LightweightMode.isEnabled &&
                _frostedGlassEnabled &&
                _savedWallpaperPath != null)
              Positioned.fill(
                // RepaintBoundary promotes the blurred wallpaper to its own GPU
                // layer so it is rasterised once, cached, and never redrawn
                // while the drawer slides — zero per-frame GPU blur cost.
                child: RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 28,
                      sigmaY: 28,
                      tileMode: TileMode.mirror,
                    ),
                    child: _savedWallpaperPath!.startsWith('assets/')
                        ? Image.asset(
                            _savedWallpaperPath!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            cacheWidth: 270,
                          )
                        : Image.file(
                            File(_savedWallpaperPath!),
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            cacheWidth: 270,
                          ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: Container(color: Theme.of(context).colorScheme.surface),
              ),
            if (!LightweightMode.isEnabled &&
                _frostedGlassEnabled &&
                _savedWallpaperPath != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.16),
                ),
              ),
            SafeArea(top: true, child: RepaintBoundary(child: childContent)),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalAppDrawer(BuildContext context) {
    final gridApps = _filteredApps;
    if (gridApps.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    // Precompute letter indices for A-Z fast scroll
    final Map<String, int> letterIndices = {};
    for (int i = 0; i < gridApps.length; i++) {
      final name = gridApps[i].name.trim();
      final firstChar = name.isNotEmpty ? name[0].toUpperCase() : '#';
      final letter = RegExp(r'[A-Z]').hasMatch(firstChar) ? firstChar : '#';
      if (!letterIndices.containsKey(letter)) {
        letterIndices[letter] = i;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - 44;
        final cellWidth = (gridWidth - (3 * 8)) / 4;
        final cellHeight = cellWidth / 0.82;
        final rowHeight = cellHeight + 12;

        return Stack(
          children: [
            // Vertical continuous scroll grid with native Stretch Overscroll
            ScrollConfiguration(
              behavior: const StretchScrollBehavior(),
              child: GridView.builder(
                controller: widget.scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 0, 36, 28),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.82,
                ),
                itemCount: gridApps.length,
                itemBuilder: (context, index) {
                  final app = gridApps[index];
                  final notificationCount = _notificationDotsEnabled
                      ? (widget.notifications[app.packageName] ?? 0)
                      : 0;
                  return _AppDrawerItem(
                    key: ValueKey('vert_${app.packageName}'),
                    app: app,
                    notificationCount: notificationCount,
                    onCloseDrawer: widget.onClose,
                    iconShape: _iconShape,
                    onDragStarted: widget.onDragStarted,
                    onDragEnded: widget.onDragEnded,
                    iconGeneration: _iconGeneration,
                  );
                },
              ),
            ),

            // A-Z Alphabet Fast Scroll Rail on right edge
            Positioned(
              right: 2,
              top: 0,
              bottom: 24,
              width: 28,
              child: _AlphabetRail(
                activeLetter: _activeAlphabetLetter,
                onLetterSelected: (letter) {
                  if (_activeAlphabetLetter != letter) {
                    HapticFeedback.selectionClick();
                    setState(() => _activeAlphabetLetter = letter);
                  }

                  int? targetIndex = letterIndices[letter];
                  if (targetIndex == null) {
                    final charCode = letter.codeUnitAt(0);
                    int minDiff = 999;
                    for (final key in letterIndices.keys) {
                      final diff = (key.codeUnitAt(0) - charCode).abs();
                      if (diff < minDiff) {
                        minDiff = diff;
                        targetIndex = letterIndices[key];
                      }
                    }
                  }

                  if (targetIndex != null && widget.scrollController.hasClients) {
                    final row = targetIndex ~/ 4;
                    final targetOffset = row * rowHeight;
                    widget.scrollController.jumpTo(
                      targetOffset.clamp(
                        0.0,
                        widget.scrollController.position.maxScrollExtent,
                      ),
                    );
                  }
                },
                onLetterReleased: () {
                  setState(() => _activeAlphabetLetter = null);
                },
              ),
            ),

            // Floating Active Letter Bubble in Center
            if (_activeAlphabetLetter != null)
              Center(
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  elevation: 8,
                  shadowColor: Colors.black45,
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: Center(
                      child: Text(
                        _activeAlphabetLetter!,
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHorizontalAppDrawer(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - 32;
        final cellWidth = (gridWidth - (3 * 8)) / 4;
        final cellHeight = cellWidth / 0.82;
        final rowHeight = cellHeight + 12;
        final totalHeight = MediaQuery.sizeOf(context).height - 160;
        final rows = (totalHeight / rowHeight).floor().clamp(1, 10);
        final itemsPerPage = rows * 4;

        final gridApps = _filteredApps;
        if (gridApps.isEmpty) return const SizedBox.shrink();

        final pages = (gridApps.length / itemsPerPage).ceil();

        return Column(
          children: [
            Expanded(
              child: ScrollConfiguration(
                behavior: const StretchScrollBehavior(),
                child: PageView.builder(
                  controller: _drawerPageController,
                  physics: const SmoothCarouselScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  itemCount: pages,
                  onPageChanged: (page) {
                    _currentPage = page;
                    _pageNotifier.value = page;
                    _prefetchPage(gridApps, itemsPerPage, page);
                    _prefetchPage(gridApps, itemsPerPage, page + 1);
                    if (page > 0) {
                      _prefetchPage(gridApps, itemsPerPage, page - 1);
                    }
                  },
                  itemBuilder: (context, pageIndex) {
                    if (pageIndex == 0) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _prefetchPage(gridApps, itemsPerPage, 0);
                          if (pages > 1) {
                            _prefetchPage(gridApps, itemsPerPage, 1);
                          }
                        }
                      });
                    }
                    final start = pageIndex * itemsPerPage;
                    final end = (start + itemsPerPage).clamp(
                      0,
                      gridApps.length,
                    );
                    final pageApps = gridApps.sublist(start, end);

                    return _AppDrawerGridPage(
                      key: ValueKey('drawer_page_$pageIndex'),
                      apps: pageApps,
                      iconShape: _iconShape,
                      notificationDotsEnabled: _notificationDotsEnabled,
                      notifications: widget.notifications,
                      onCloseDrawer: widget.onClose,
                      onDragStarted: widget.onDragStarted,
                      onDragEnded: widget.onDragEnded,
                      iconGeneration: _iconGeneration,
                    );
                  },
                ),
              ),
            ),
            if (pages > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ValueListenableBuilder<int>(
                  valueListenable: _pageNotifier,
                  builder: (context, currentPage, _) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(pages, (index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: currentPage == index
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.2),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── App Drawer Grid Page (Preserved in Memory) ─────────────────────────────

class _AppDrawerGridPage extends StatefulWidget {
  final List<AppInfo> apps;
  final String iconShape;
  final bool notificationDotsEnabled;
  final Map<String, int> notifications;
  final VoidCallback onCloseDrawer;
  final void Function(String packageName)? onDragStarted;
  final VoidCallback? onDragEnded;
  final int iconGeneration;

  const _AppDrawerGridPage({
    super.key,
    required this.apps,
    required this.iconShape,
    required this.notificationDotsEnabled,
    required this.notifications,
    required this.onCloseDrawer,
    this.onDragStarted,
    this.onDragEnded,
    required this.iconGeneration,
  });

  @override
  State<_AppDrawerGridPage> createState() => _AppDrawerGridPageState();
}

class _AppDrawerGridPageState extends State<_AppDrawerGridPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemCount: widget.apps.length,
      itemBuilder: (context, index) {
        final app = widget.apps[index];
        final notificationCount = widget.notificationDotsEnabled
            ? (widget.notifications[app.packageName] ?? 0)
            : 0;
        return _AppDrawerItem(
          key: ValueKey(app.packageName),
          app: app,
          notificationCount: notificationCount,
          onCloseDrawer: widget.onCloseDrawer,
          iconShape: widget.iconShape,
          onDragStarted: widget.onDragStarted,
          onDragEnded: widget.onDragEnded,
          iconGeneration: widget.iconGeneration,
        );
      },
    );
  }
}

// ─── App Drawer Item ─────────────────────────────────────────────────────────

class _AppDrawerItem extends StatefulWidget {
  final AppInfo app;
  final int notificationCount;
  final VoidCallback onCloseDrawer;
  final String iconShape;
  final void Function(String packageName)? onDragStarted;
  final VoidCallback? onDragEnded;
  final int iconGeneration;

  const _AppDrawerItem({
    super.key,
    required this.app,
    required this.notificationCount,
    required this.onCloseDrawer,
    required this.iconShape,
    this.onDragStarted,
    this.onDragEnded,
    required this.iconGeneration,
  });

  @override
  State<_AppDrawerItem> createState() => _AppDrawerItemState();
}

class _AppDrawerItemState extends State<_AppDrawerItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static final Map<String, Uint8List> _renderedIconCache = {};
  static int _cachedIconGeneration = -1;

  bool _dragStarted = false;
  Uint8List? _icon;
  int _iconLoadGeneration = 0;
  final GlobalKey _iconBoxKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (_cachedIconGeneration != widget.iconGeneration) {
      _renderedIconCache.clear();
      _cachedIconGeneration = widget.iconGeneration;
    }
    _icon = _renderedIconCache[widget.app.packageName] ??
        widget.app.icon ??
        AppDatabaseService.getCachedIcon(widget.app.packageName);
    if (_icon != null) {
      _renderedIconCache[widget.app.packageName] = _icon!;
    } else {
      _loadIcon();
    }
  }

  @override
  void didUpdateWidget(covariant _AppDrawerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName ||
        oldWidget.iconGeneration != widget.iconGeneration) {
      _iconLoadGeneration++;
      if (oldWidget.iconGeneration != widget.iconGeneration) {
        _renderedIconCache.clear();
        _cachedIconGeneration = widget.iconGeneration;
      }
      _icon = _renderedIconCache[widget.app.packageName] ??
          widget.app.icon ??
          AppDatabaseService.getCachedIcon(widget.app.packageName);
      if (_icon == null) {
        _loadIcon();
      } else {
        setState(() {});
      }
    }
  }

  Future<void> _loadIcon() async {
    final generation = ++_iconLoadGeneration;
    if (widget.app.icon != null) {
      _renderedIconCache[widget.app.packageName] = widget.app.icon!;
      if (mounted) setState(() => _icon = widget.app.icon);
      return;
    }

    final cached = AppDatabaseService.getCachedIcon(widget.app.packageName);
    if (cached != null) {
      _renderedIconCache[widget.app.packageName] = cached;
      if (mounted) setState(() => _icon = cached);
      return;
    }

    final icon = await AppDatabaseService.loadIcon(widget.app.packageName);
    if (icon != null) {
      _renderedIconCache[widget.app.packageName] = icon;
    }
    if (!mounted || generation != _iconLoadGeneration) return;
    setState(() => _icon = icon);
  }

  void _showContextMenu(BuildContext context) {
    final app = widget.app;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _icon != null
                          ? Image.memory(
                              _icon!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              cacheWidth: 120,
                            )
                          : _AppPlaceholder(
                              name: app.name,
                              size: 40,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        app.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.launch_rounded, color: cs.primary),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(ctx);
                  AppLockService.launchApp(context, app.packageName);
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline_rounded, color: cs.primary),
                title: const Text('App Info'),
                onTap: () {
                  Navigator.pop(ctx);
                  LauncherService.openAppInfo(app.packageName);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                title: Text('Uninstall', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  LauncherService.uninstallApp(app.packageName);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final app = widget.app;
    final icon = _icon ?? AppDatabaseService.getCachedIcon(app.packageName);
    final appItemData = _WorkspaceItemData(
      packageName: app.packageName,
      label: app.name,
    ).toMap();

    return LongPressDraggable<Map<String, dynamic>>(
      data: appItemData,
      delay: const Duration(milliseconds: 400),
      onDragStarted: () {
        _dragStarted = true;
        widget.onCloseDrawer();
        widget.onDragStarted?.call(app.packageName);
      },
      onDragEnd: (_) {
        _dragStarted = false;
        widget.onDragEnded?.call();
      },
      onDraggableCanceled: (velocity, offset) {
        _dragStarted = false;
        widget.onDragEnded?.call();
      },
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconShapeClipper(
                shape: widget.iconShape,
                size: 56,
                child: icon != null
                    ? Image.memory(
                        icon,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        cacheWidth: 168,
                        gaplessPlayback: true,
                      )
                    : _AppPlaceholder(
                        name: app.name,
                        size: 56,
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                app.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.25,
        child: Column(
          children: [
            IconShapeClipper(
              shape: widget.iconShape,
              size: 48,
              child: icon != null
                  ? Image.memory(
                      icon,
                      width: 48,
                      height: 48,
                      cacheWidth: 144,
                      gaplessPlayback: true,
                    )
                  : _AppPlaceholder(
                      name: app.name,
                      size: 48,
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              app.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () {
          final renderBox =
              _iconBoxKey.currentContext?.findRenderObject() as RenderBox? ??
              context.findRenderObject() as RenderBox?;
          final bounds = (renderBox != null && renderBox.hasSize)
              ? (renderBox.localToGlobal(Offset.zero) & renderBox.size)
              : null;
          widget.onCloseDrawer();
          AppLockService.launchApp(
            context,
            app.packageName,
            sourceBounds: bounds,
            fromDrawer: true,
          );
        },
        onLongPress: () {
          if (!_dragStarted) {
            _showContextMenu(context);
          }
        },
        child: Column(
          children: [
            Stack(
              children: [
                SizedBox(
                  key: _iconBoxKey,
                  width: 48,
                  height: 48,
                  child: IconShapeClipper(
                    shape: widget.iconShape,
                    size: 48,
                    child: icon != null
                        ? Image.memory(
                            icon,
                            key: ValueKey('icon_${app.packageName}'),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            cacheWidth: 144,
                            gaplessPlayback: true,
                          )
                        : _AppPlaceholder(
                            key: ValueKey('placeholder_${app.packageName}'),
                            name: app.name,
                            size: 48,
                          ),
                  ),
                ),
                if (widget.notificationCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cs.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${widget.notificationCount}',
                        style: TextStyle(
                          color: cs.onError,
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
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppPlaceholder extends StatelessWidget {
  final String name;
  final double size;

  const _AppPlaceholder({
    super.key,
    required this.name,
    required this.size,
  });

  static const List<Color> _palette = [
    Color(0xFFE57373),
    Color(0xFFF06292),
    Color(0xFFBA68C8),
    Color(0xFF9575CD),
    Color(0xFF7986CB),
    Color(0xFF64B5F6),
    Color(0xFF4FC3F7),
    Color(0xFF4DD0E1),
    Color(0xFF4DB6AC),
    Color(0xFF81C784),
    Color(0xFFAED581),
    Color(0xFFFFB74D),
    Color(0xFFFF8A65),
    Color(0xFFA1887F),
    Color(0xFF90A4AE),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final color = _palette[trimmed.hashCode.abs() % _palette.length];

    return Container(
      width: size,
      height: size,
      color: color.withValues(alpha: 0.85),
    );
  }
}

class SmoothCarouselScrollPhysics extends PageScrollPhysics {
  const SmoothCarouselScrollPhysics({super.parent});

  @override
  SmoothCarouselScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SmoothCarouselScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.5,
        stiffness: 100.0,
        damping: 14.2,
      );
}

// ─── A–Z Fast Scroll Alphabet Rail ──────────────────────────────────────────

class _AlphabetRail extends StatelessWidget {
  final String? activeLetter;
  final ValueChanged<String> onLetterSelected;
  final VoidCallback onLetterReleased;

  const _AlphabetRail({
    required this.activeLetter,
    required this.onLetterSelected,
    required this.onLetterReleased,
  });

  static const List<String> _letters = [
    '#',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  void _handleTouch(Offset localPos, double height) {
    final itemHeight = height / _letters.length;
    final index =
        (localPos.dy / itemHeight).floor().clamp(0, _letters.length - 1);
    onLetterSelected(_letters[index]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) =>
              _handleTouch(d.localPosition, constraints.maxHeight),
          onVerticalDragUpdate: (d) =>
              _handleTouch(d.localPosition, constraints.maxHeight),
          onVerticalDragEnd: (_) => onLetterReleased(),
          onVerticalDragCancel: onLetterReleased,
          onTapDown: (d) =>
              _handleTouch(d.localPosition, constraints.maxHeight),
          onTapUp: (_) => onLetterReleased(),
          onTapCancel: onLetterReleased,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _letters.map((letter) {
                final isSelected = activeLetter == letter;
                return Text(
                  letter,
                  style: TextStyle(
                    fontSize: 8.0,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class StretchScrollBehavior extends MaterialScrollBehavior {
  const StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
