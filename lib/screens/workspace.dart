import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:soft_edge_blur/soft_edge_blur.dart';
import 'package:flutter/material.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:installed_apps/app_info.dart';
import 'package:swavoti/screens/home_screen.dart';
import 'package:swavoti/screens/app_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Workspace extends StatefulWidget {
  final SharedPreferences prefs;
  final Map<String, AppInfo> appCache;
  const Workspace({super.key, required this.prefs, required this.appCache});

  @override
  State<Workspace> createState() => WorkspaceState();
}

class WorkspaceState extends State<Workspace>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  Map<String, int> _notifications = {};
  StreamSubscription<Map<String, int>>? _notificationSubscription;

  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();
  final GlobalKey<AppDrawerState> _appDrawerKey = GlobalKey<AppDrawerState>();

  // ── Custom drawer animation ──────────────────────────────────────────────
  late AnimationController _drawerController;
  bool _drawerOpen = false;
  double? _dragStartY;
  double? _dragStartExtent;

  // Default launcher banner
  bool _isDefaultLauncher = true;
  bool _bannerDismissed = false;

  // The scroll controller the AppDrawer's inner list uses
  final ScrollController _drawerScrollController = ScrollController();

  Future<void> refreshLauncherSettings() async {
    await _homeScreenKey.currentState?.refreshSettings();
    await _appDrawerKey.currentState?.loadSettings();
  }

  void clearTransientMemoryCaches() {
    _appDrawerKey.currentState?.clearIconCache();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDefaultLauncher();

    _drawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 0.0,
    );

    try {
      _notificationSubscription = LauncherService.notificationsStream.listen(
        (data) {
          if (mounted && !mapEquals(_notifications, data)) {
            setState(() => _notifications = data);
          }
        },
        onError: (e) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep hot in RAM; no-op
  }

  Future<void> _checkDefaultLauncher() async {
    final isDefault = await LauncherService.isDefaultLauncher();
    if (mounted) setState(() => _isDefaultLauncher = isDefault);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    _drawerController.dispose();
    _drawerScrollController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    _appDrawerKey.currentState?.prefetchFirstPage();
    _homeScreenKey.currentState?.setExternalOverlayOpen(true);
    _drawerController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    setState(() => _drawerOpen = true);
  }

  void _closeDrawer() {
    _drawerController
        .animateTo(
          0.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (mounted && !_drawerOpen) {
            _homeScreenKey.currentState?.setExternalOverlayOpen(false);
          }
        });
    setState(() => _drawerOpen = false);
  }

  bool _isItemDragging = false;

  void _onDragStarted(String packageName) {
    if (!_isItemDragging) {
      setState(() => _isItemDragging = true);
    }
  }

  void _onDragEnded() {
    if (_isItemDragging) {
      setState(() => _isItemDragging = false);
    }
  }

  // ── Finger-tracking gesture handlers ─────────────────────────────────────

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isItemDragging) return;
    _appDrawerKey.currentState?.prefetchFirstPage();
    _homeScreenKey.currentState?.setExternalOverlayOpen(true);
    _dragStartY = details.globalPosition.dy;
    _dragStartExtent = _drawerController.value;
    _drawerController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isItemDragging || _dragStartY == null || _dragStartExtent == null) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final dy = details.globalPosition.dy - _dragStartY!;
    final newExtent = (_dragStartExtent! - dy / screenHeight).clamp(0.0, 1.0);
    _drawerController.value = newExtent;
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragStartY = null;
    _dragStartExtent = null;
    final velocity = -(details.primaryVelocity ?? 0);
    final extent = _drawerController.value;

    if (velocity > 180) {
      _openDrawer();
    } else if (velocity < -180) {
      _closeDrawer();
    } else if (extent >= 0.25) {
      _openDrawer();
    } else {
      _closeDrawer();
    }
  }

  void _onDrawerDragStart(DragStartDetails details) {
    final atTop =
        !_drawerScrollController.hasClients ||
        _drawerScrollController.position.pixels <= 0;
    if (!atTop) return;
    _dragStartY = details.globalPosition.dy;
    _dragStartExtent = _drawerController.value;
    _drawerController.stop();
  }

  void _onDrawerDragUpdate(DragUpdateDetails details) {
    if (_dragStartY == null || _dragStartExtent == null) return;
    final dy = details.globalPosition.dy - _dragStartY!;
    if (dy < 0) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final newExtent = (_dragStartExtent! - dy / screenHeight).clamp(0.0, 1.0);
    _drawerController.value = newExtent;
  }

  void _onDrawerDragEnd(DragEndDetails details) {
    if (_dragStartY == null) return;
    _dragStartY = null;
    _dragStartExtent = null;
    final velocity = details.primaryVelocity ?? 0;
    final extent = _drawerController.value;

    if (velocity > 180) {
      _closeDrawer();
    } else if (velocity < -180) {
      _openDrawer();
    } else if (extent <= 0.75) {
      _closeDrawer();
    } else {
      _openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_drawerOpen) _closeDrawer();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── Home Screen ─────────────────────────────────────────
            AnimatedBuilder(
              animation: _drawerController,
              builder: (context, child) {
                final drawerDrag = _drawerController.value;
                return Transform.translate(
                  offset: Offset(
                    0,
                    -screenHeight * 0.16 * drawerDrag,
                  ),
                  child: Transform.scale(
                    scale: 1.0 - 0.05 * drawerDrag,
                    child: Opacity(
                      opacity: (1.0 - drawerDrag * 2.8).clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                );
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _isItemDragging ? null : _onVerticalDragStart,
                onVerticalDragUpdate: _isItemDragging
                    ? null
                    : (details) {
                        final dy = details.primaryDelta ?? 0;
                        if (dy > 8 && _drawerController.value < 0.05) {
                          LauncherService.expandNotifications();
                          return;
                        }
                        _onVerticalDragUpdate(details);
                      },
                onVerticalDragEnd: _isItemDragging ? null : _onVerticalDragEnd,
                child: HomeScreen(
                  key: _homeScreenKey,
                  prefs: widget.prefs,
                  appCache: widget.appCache,
                  notifications: _notifications,
                  onSettingsChanged: () {
                    _appDrawerKey.currentState?.loadSettings();
                  },
                  onDragStarted: _onDragStarted,
                  onDragEnded: _onDragEnded,
                ),
              ),
            ),

            // ── App Drawer (finger-tracking slide) ─────────────────
            AnimatedBuilder(
              animation: _drawerController,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  0,
                  screenHeight * (1.0 - _drawerController.value),
                ),
                child: child,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onDrawerDragStart,
                onVerticalDragUpdate: _onDrawerDragUpdate,
                onVerticalDragEnd: _onDrawerDragEnd,
                child: SizedBox(
                  height: screenHeight,
                  child: ScrollConfiguration(
                    behavior: const StretchScrollBehavior(),
                    child: AppDrawer(
                      key: _appDrawerKey,
                      notifications: _notifications,
                      onClose: _closeDrawer,
                      scrollController: _drawerScrollController,
                      onDragStarted: _onDragStarted,
                      onDragEnded: _onDragEnded,
                      preloadedAppCache: widget.appCache,
                    ),
                  ),
                ),
              ),
            ),

            // ── Default Launcher Banner ──────────────────────────────
            if (!_isDefaultLauncher && !_bannerDismissed)
              Positioned(
                bottom: bottomPadding + 110,
                left: 16,
                right: 16,
                child: _DefaultLauncherBanner(
                  onDismiss: () => setState(() => _bannerDismissed = true),
                  onSetDefault: () async {
                    await LauncherService.openDefaultLauncherSettings();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Default Launcher Banner ─────────────────────────────────────────────────

class _DefaultLauncherBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  final VoidCallback onSetDefault;

  const _DefaultLauncherBanner({
    required this.onDismiss,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SoftEdgeBlur(
        edges: [
          EdgeBlur(
            type: EdgeType.topEdge,
            size: 100,
            sigma: 30,
            controlPoints: [
              ControlPoint(position: 0.5, type: ControlPointType.visible),
              ControlPoint(position: 1, type: ControlPointType.transparent),
            ],
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.home_outlined,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Set as default home app for the full experience',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onSetDefault,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Set Default'),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
