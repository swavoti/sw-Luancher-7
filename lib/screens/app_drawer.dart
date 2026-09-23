import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/widgets/icon_shape_clipper.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  _WorkspaceItemData({
    required this.packageName,
    required this.label,
  });

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

  // A-Z sidebar
  final Map<String, int> _letterIndex = {}; // letter -> first grid index
  OverlayEntry? _letterOverlay;

  // Grid scroll key for alphabet jump
  final GlobalKey _gridKey = GlobalKey();

  // Approximate row height in the grid
  static const double _cellSize = 90.0; // approx icon cell height
  static const int _gridColumns = 4;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _loadIconShape();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _letterOverlay?.remove();
    super.dispose();
  }

  Future<void> _loadIconShape() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _iconShape = prefs.getString('icon_shape') ?? 'Circle';
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

    final metaApps = filterApps(await AppDatabaseService.getAppMetadata());
    if (metaApps.isNotEmpty && mounted) {
      setState(() {
        _apps = metaApps;
        _filteredApps = metaApps;
        _isLoading = false;
      });
      _buildLetterIndex(metaApps);
    }

    AppDatabaseService.syncAppsBackground().then((freshApps) {
      if (!mounted) return;
      final apps = filterApps(freshApps);
      setState(() {
        _apps = apps;
        _filteredApps = apps;
        _isLoading = false;
      });
      _buildLetterIndex(apps);
    });
  }

  void _buildLetterIndex(List<AppInfo> apps) {
    _letterIndex.clear();
    for (int i = 0; i < apps.length; i++) {
      final firstChar = apps[i].name.isNotEmpty
          ? apps[i].name[0].toUpperCase()
          : '#';
      if (!_letterIndex.containsKey(firstChar)) {
        _letterIndex[firstChar] = i;
      }
    }
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps = _apps
          .where((app) => app.name.toLowerCase().contains(query))
          .toList();
    });
    _buildLetterIndex(_filteredApps);
  }

  void _jumpToLetter(String letter) {
    final index = _letterIndex[letter];
    if (index == null) return;

    // Header sliver height estimate: search bar (~56) + top padding (~32) + suggested apps (~120) + divider(~20) = ~228
    const headerHeight = 228.0;
    final row = (index / _gridColumns).floor();
    final offset = headerHeight + row * _cellSize;

    widget.scrollController.animateTo(
      offset.clamp(0.0, widget.scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _showLetterBubble(String letter) {
    _letterOverlay?.remove();
    final overlay = Overlay.of(context);
    _letterOverlay = OverlayEntry(
      builder: (context) => Center(
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                letter,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_letterOverlay!);
    Future.delayed(const Duration(milliseconds: 700), () {
      _letterOverlay?.remove();
      _letterOverlay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          // Main drawer content
          Expanded(
            child: CustomScrollView(
              controller: widget.scrollController,
              // AlwaysScrollableScrollPhysics lets the sheet collapse on
              // drag-down even when the list is at the top — no more fighting
              // the bouncing behaviour that traps the user mid-way.
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Column(
                      children: [
                        // Pull handle
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Search box — compact rect with rounded edges + mic
                        SizedBox(
                          height: 44,
                          child: TextField(
                            controller: _searchController,
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search apps',
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.65),
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                size: 20,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _searchController.clear(),
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        Icons.mic_rounded,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        size: 20,
                                      ),
                                      onPressed:
                                          LauncherService.openGoogleVoiceSearch,
                                    ),
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.55),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Suggested row (first 4 apps)
                        if (_searchController.text.isEmpty &&
                            _filteredApps.length >= 4) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: _filteredApps.take(4).map((app) {
                              final notificationCount =
                                  widget.notifications[app.packageName] ?? 0;
                              return Expanded(
                                child: _AppDrawerItem(
                                  app: app,
                                  notificationCount: notificationCount,
                                  onCloseDrawer: widget.onClose,
                                  iconShape: _iconShape,
                                  onDragStarted: widget.onDragStarted,
                                  onDragEnded: widget.onDragEnded,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_isLoading)
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else if (_filteredApps.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No apps found.')),
                    ),
                  )
                else
                  SliverPadding(
                    key: _gridKey,
                    padding: const EdgeInsets.fromLTRB(16, 0, 0, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _gridColumns,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.82,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final app = _filteredApps[index];
                        final notificationCount =
                            widget.notifications[app.packageName] ?? 0;
                        return _AppDrawerItem(
                          app: app,
                          notificationCount: notificationCount,
                          onCloseDrawer: widget.onClose,
                          iconShape: _iconShape,
                          onDragStarted: widget.onDragStarted,
                          onDragEnded: widget.onDragEnded,
                        );
                      }, childCount: _filteredApps.length),
                    ),
                  ),
              ],
            ),
          ),

          // A-Z Sidebar
          if (_searchController.text.isEmpty)
            _AlphabetSidebar(
              letterIndex: _letterIndex,
              onLetterTap: (letter) {
                _jumpToLetter(letter);
                _showLetterBubble(letter);
              },
            ),
        ],
      ),
    );
  }
}

// ─── Alphabet Sidebar ────────────────────────────────────────────────────────

class _AlphabetSidebar extends StatefulWidget {
  final Map<String, int> letterIndex;
  final void Function(String letter) onLetterTap;

  const _AlphabetSidebar({
    required this.letterIndex,
    required this.onLetterTap,
  });

  @override
  State<_AlphabetSidebar> createState() => _AlphabetSidebarState();
}

class _AlphabetSidebarState extends State<_AlphabetSidebar> {
  String? _pressed;
  static const List<String> _allLetters = [
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
    '#',
  ];

  void _handleTouch(Offset localPosition, double sidebarHeight) {
    final fraction = (localPosition.dy / sidebarHeight).clamp(0.0, 1.0);
    final idx = (fraction * (_allLetters.length - 1)).round();
    final letter = _allLetters[idx];
    if (letter != _pressed && widget.letterIndex.containsKey(letter)) {
      setState(() => _pressed = letter);
      widget.onLetterTap(letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) _handleTouch(d.localPosition, box.size.height);
      },
      onVerticalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) _handleTouch(d.localPosition, box.size.height);
      },
      onVerticalDragEnd: (_) => setState(() => _pressed = null),
      onTapUp: (_) => setState(() => _pressed = null),
      child: Container(
        width: 22,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _allLetters.map((l) {
            final hasApps = widget.letterIndex.containsKey(l);
            final isPressed = _pressed == l;
            return Text(
              l,
              style: TextStyle(
                fontSize: isPressed ? 13 : 10,
                fontWeight: isPressed ? FontWeight.bold : FontWeight.normal,
                color: hasApps
                    ? (isPressed
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface)
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
              ),
            );
          }).toList(),
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

  const _AppDrawerItem({
    required this.app,
    required this.notificationCount,
    required this.onCloseDrawer,
    required this.iconShape,
    this.onDragStarted,
    this.onDragEnded,
  });

  @override
  State<_AppDrawerItem> createState() => _AppDrawerItemState();
}

class _AppDrawerItemState extends State<_AppDrawerItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = widget.app;
    final icon = app.icon;
    final appItemData = _WorkspaceItemData(
      packageName: app.packageName,
      label: app.name,
    ).toMap();

    return LongPressDraggable<Map<String, dynamic>>(
      data: appItemData,
      delay: const Duration(milliseconds: 150),
      onDragStarted: () {
        widget.onCloseDrawer();
        widget.onDragStarted?.call(app.packageName);
      },
      onDragEnd: (_) => widget.onDragEnded?.call(),
      onDraggableCanceled: (_, _) => widget.onDragEnded?.call(),
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
                ? Image.memory(icon, width: 48, height: 48)
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
