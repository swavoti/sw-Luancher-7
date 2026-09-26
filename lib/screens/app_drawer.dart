import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/widgets/icon_shape_clipper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:typed_data';

class AppDrawer extends StatefulWidget {
  final Map<String, int> notifications;
  final VoidCallback onClose;
  final void Function(Map<String, dynamic>)? onAddToHomeScreen;
  final ScrollController scrollController;
  final void Function(String packageName)? onDragStarted;
  final VoidCallback? onDragEnded;

  const AppDrawer({
    super.key,
    required this.notifications,
    required this.onClose,
    this.onAddToHomeScreen,
    required this.scrollController,
    this.onDragStarted,
    this.onDragEnded,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
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

class _AppDrawerState extends State<AppDrawer> {
  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _iconShape = 'Circle';
  bool _frostedGlassEnabled = true;
  int _currentPage = 0;

  // Grid scroll key
  final GlobalKey _gridKey = GlobalKey();

  // Approximate row height in the grid
  static const double _cellSize = 90.0; // approx icon cell height
  static const int _gridColumns = 4;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _loadSettings();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? _savedWallpaperPath;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _iconShape = prefs.getString('icon_shape') ?? 'Circle';
        _frostedGlassEnabled = prefs.getBool('frosted_glass_enabled') ?? true;
        _savedWallpaperPath = prefs.getString('saved_wallpaper_path');
      });
    }
  }

  Future<void> _loadApps() async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getStringList('hidden_apps') ?? [];
    final showHidden = prefs.getBool('show_hidden_apps') ?? false;

    List<AppInfo> filterApps(List<AppInfo> apps) {
      if (showHidden) return apps;
      return apps.where((a) => !hidden.contains(a.packageName)).toList();
    }

    // Try fast DB path first
    final metaApps = filterApps(await AppDatabaseService.getAppMetadata());
    if (mounted) {
      setState(() {
        if (metaApps.isNotEmpty) {
          _apps = metaApps;
          _filteredApps = metaApps;
        }
        // Always unblock the loading state — fresh sync below will populate
        // if the DB happened to be empty (first install / post-wipe).
        _isLoading = metaApps.isEmpty; // keep spinner only if truly empty
      });
      if (metaApps.isNotEmpty) {
        AppDatabaseService.prefetchIcons(metaApps.map((a) => a.packageName));
      }
    }

    // Always run fresh sync from the OS
    AppDatabaseService.syncAppsBackground().then((freshApps) {
      if (!mounted) return;
      if (freshApps.isNotEmpty) {
        final apps = filterApps(freshApps);
        setState(() {
          _apps = apps;
          _filteredApps = apps;
          _isLoading = false;
        });
        AppDatabaseService.prefetchIcons(apps.map((a) => a.packageName));
      } else {
        // syncAppsBackground returned empty — fall back to direct OS fetch
        // as a last resort so the drawer is never permanently stuck.
        InstalledApps.getInstalledApps(
          excludeSystemApps: false,
          excludeNonLaunchableApps: true,
          withIcon: false,
        ).then((osFresh) {
          if (!mounted) return;
          final apps = filterApps(osFresh);
          setState(() {
            _apps = apps;
            _filteredApps = apps;
            _isLoading = false;
          });
          AppDatabaseService.prefetchIcons(apps.map((a) => a.packageName));
        }).catchError((_) {
          if (mounted) setState(() => _isLoading = false);
        });
      }
    });

  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps = _apps
          .where((app) => app.name.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final childContent = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        FocusScope.of(context).requestFocus(FocusNode()),
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
                          _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () => _searchController.clear(),
                                  padding: EdgeInsets.zero,
                                )
                              : IconButton(
                                  icon: Icon(
                                    Icons.mic_rounded,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: 20,
                                  ),
                                  onPressed:
                                      LauncherService.openGoogleVoiceSearch,
                                  padding: EdgeInsets.zero,
                                ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final gridWidth = constraints.maxWidth - 32; // padding
                    final cellWidth =
                        (gridWidth - (3 * 8)) / 4; // 3 crossAxisSpacing
                    final cellHeight = cellWidth / 0.82;
                    final rowHeight = cellHeight + 12; // mainAxisSpacing
                    final rows = (constraints.maxHeight / rowHeight)
                        .floor()
                        .clamp(1, 10);
                    final itemsPerPage = rows * 4;

                    final gridApps = _filteredApps;

                    if (gridApps.isEmpty) return const SizedBox.shrink();

                    final pages = (gridApps.length / itemsPerPage).ceil();

                    return Column(
                      children: [
                        Expanded(
                          child: PageView.builder(
                            itemCount: pages,
                            onPageChanged: (page) {
                              setState(() {
                                _currentPage = page;
                              });
                            },
                            itemBuilder: (context, pageIndex) {
                              final start = pageIndex * itemsPerPage;
                              final end = (start + itemsPerPage).clamp(
                                0,
                                gridApps.length,
                              );
                              final pageApps = gridApps.sublist(start, end);

                              return GridView.builder(
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 8,
                                      childAspectRatio: 0.82,
                                    ),
                                itemCount: pageApps.length,
                                itemBuilder: (context, index) {
                                  final app = pageApps[index];
                                  final notificationCount =
                                      widget.notifications[app.packageName] ??
                                      0;
                                  return _AppDrawerItem(
                                    key: ValueKey(app.packageName),
                                    app: app,
                                    notificationCount: notificationCount,
                                    onCloseDrawer: widget.onClose,
                                    iconShape: _iconShape,
                                    onDragStarted: widget.onDragStarted,
                                    onDragEnded: widget.onDragEnded,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        if (pages > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(pages, (index) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentPage == index
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.2),
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            if (_frostedGlassEnabled && _savedWallpaperPath != null)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Image.asset(
                    _savedWallpaperPath!,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              )
            else
              Positioned.fill(
                child: Container(color: Theme.of(context).colorScheme.surface),
              ),
            childContent,
          ],
        ),
      ),
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
  final void Function(Map<String, dynamic>)? onAddToHomeScreen;

  const _AppDrawerItem({
    super.key,
    required this.app,
    required this.notificationCount,
    required this.onCloseDrawer,
    required this.iconShape,
    this.onDragStarted,
    this.onDragEnded,
    this.onAddToHomeScreen,
  });

  @override
  State<_AppDrawerItem> createState() => _AppDrawerItemState();
}

class _AppDrawerItemState extends State<_AppDrawerItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _dragStarted = false;
  Uint8List? _icon;

  @override
  void initState() {
    super.initState();
    _icon =
        widget.app.icon ??
        AppDatabaseService.getCachedIcon(widget.app.packageName);
    if (_icon == null) _loadIcon();
  }

  @override
  void didUpdateWidget(covariant _AppDrawerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) {
      _icon =
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
    if (widget.app.icon != null) {
      if (mounted) setState(() => _icon = widget.app.icon);
      return;
    }

    final icon = await AppDatabaseService.loadIcon(widget.app.packageName);
    if (mounted) {
      setState(() => _icon = icon);
    }
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
                    if (_icon != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _icon!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          cacheWidth: 120,
                        ),
                      )
                    else
                      Icon(Icons.android, size: 40, color: cs.primary),
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
                  LauncherService.startApp(app.packageName);
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
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: const Text(
                  'Uninstall',
                  style: TextStyle(color: Colors.red),
                ),
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
    final app = widget.app;
    final icon = _icon;
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
      onDraggableCanceled: (_, __) {
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
                    : const Icon(Icons.android, size: 56),
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
            icon != null
                ? Image.memory(icon, width: 48, height: 48, cacheWidth: 144)
                : const Icon(Icons.android, size: 48),
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
        onTap: () => LauncherService.startApp(app.packageName),
        onLongPress: () {
          // If drag didn't activate, show context menu
          if (!_dragStarted) {
            _showContextMenu(context);
          }
        },
        child: Column(
          children: [
            Stack(
              children: [
                IconShapeClipper(
                  shape: widget.iconShape,
                  size: 48,
                  child: icon != null
                      ? Image.memory(
                          icon,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          gaplessPlayback: true,
                        )
                      : const Icon(Icons.android, size: 48),
                ),
                if (widget.notificationCount > 0)
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
                        '${widget.notificationCount}',
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
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
