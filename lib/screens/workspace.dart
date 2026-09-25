import 'dart:async';
import 'dart:ui';
import 'package:soft_edge_blur/soft_edge_blur.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  Map<String, int> _notifications = {};
  StreamSubscription<Map<String, int>>? _notificationSubscription;

  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();

  // ── Custom drawer animation ──────────────────────────────────────────────
  late AnimationController _drawerController;
  double _drawerDrag = 0.0; // 0 = closed, 1 = open
  bool _drawerOpen = false;
  double? _dragStartY;
  double? _dragStartExtent;

  // Discover page animation
  late final AnimationController _discoverController;
  late final Animation<double> _discoverAnimation;

  // Drag bubble state
  String? _draggingPackage;
  bool _isDragging = false;

  // Default launcher banner
  bool _isDefaultLauncher = true;
  bool _bannerDismissed = false;

  // The scroll controller the AppDrawer's inner list uses
  final ScrollController _drawerScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDefaultLauncher();

    _drawerController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 340),
          value: 0.0,
        )..addListener(() {
          if (mounted) setState(() => _drawerDrag = _drawerController.value);
        });

    _discoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _discoverAnimation = CurvedAnimation(
      parent: _discoverController,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInQuart,
    );

    try {
      _notificationSubscription = LauncherService.notificationsStream.listen(
        (data) {
          if (mounted) setState(() => _notifications = data);
        },
        onError: (e) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDefaultLauncher();
    }
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
    _discoverController.dispose();
    _drawerScrollController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    _drawerController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutQuart,
    );
    setState(() => _drawerOpen = true);
  }

  void _closeDrawer() {
    _drawerController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInQuart,
    );
    setState(() => _drawerOpen = false);
    // Reset the inner scroll to top so it's fresh on next open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_drawerScrollController.hasClients) {
        _drawerScrollController.jumpTo(0);
      }
    });
  }

  void _openDiscover() => _discoverController.forward();
  void _closeDiscover() => _discoverController.reverse();

  void _onDragStarted(String packageName) {
    setState(() {
      _draggingPackage = packageName;
      _isDragging = true;
    });
  }

  void _onDragEnded() {
    setState(() {
      _draggingPackage = null;
      _isDragging = false;
    });
  }

  // ── Finger-tracking gesture handlers ─────────────────────────────────────

  void _onVerticalDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _dragStartExtent = _drawerController.value;
    // Stop any in-progress animation
    _drawerController.stop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_dragStartY == null || _dragStartExtent == null) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final dy = details.globalPosition.dy - _dragStartY!;
    // Upward = negative dy = opening drawer
    final newExtent = (_dragStartExtent! - dy / screenHeight).clamp(0.0, 1.0);
    _drawerController.value = newExtent;
    setState(() => _drawerDrag = newExtent);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragStartY = null;
    _dragStartExtent = null;
    final velocity = -(details.primaryVelocity ?? 0); // positive = swiping up
    final extent = _drawerController.value;

    if (velocity > 300) {
      _openDrawer();
    } else if (velocity < -300) {
      _closeDrawer();
    } else if (extent > 0.4) {
      _openDrawer();
    } else {
      _closeDrawer();
    }
  }

  // Handle vertical drag on the drawer itself (for closing)
  void _onDrawerDragStart(DragStartDetails details) {
    // Only handle if the inner scroll is at the top
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
    // Only allow drag-down to close
    final dy = details.globalPosition.dy - _dragStartY!;
    if (dy < 0) return; // ignore upward drags inside open drawer
    final screenHeight = MediaQuery.of(context).size.height;
    final newExtent = (_dragStartExtent! - dy / screenHeight).clamp(0.0, 1.0);
    _drawerController.value = newExtent;
    setState(() => _drawerDrag = newExtent);
  }

  void _onDrawerDragEnd(DragEndDetails details) {
    if (_dragStartY == null) return;
    _dragStartY = null;
    _dragStartExtent = null;
    final velocity = details.primaryVelocity ?? 0; // positive = swiping down
    final extent = _drawerController.value;

    if (velocity > 400) {
      _closeDrawer();
    } else if (velocity < -400) {
      _openDrawer();
    } else if (extent > 0.6) {
      _openDrawer();
    } else {
      _closeDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final drawerOffsetY = screenHeight * (1.0 - _drawerDrag);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_drawerOpen) _closeDrawer();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // ── Home Screen ─────────────────────────────────────────
            AnimatedBuilder(
              animation: _discoverAnimation,
              builder: (context, child) {
                final screenWidth = MediaQuery.of(context).size.width;
                final discoverExtent = _discoverAnimation.value;
                return Transform.translate(
                  offset: Offset(
                    screenWidth * 0.25 * discoverExtent,
                    -screenHeight * 0.18 * _drawerDrag,
                  ),
                  child: Transform.scale(
                    scale: 1.0 - 0.05 * _drawerDrag,
                    child: Opacity(
                      opacity:
                          ((1.0 - _drawerDrag * 3.0) *
                                  (1.0 - discoverExtent * 0.7))
                              .clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                );
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: (details) {
                  final dy = details.primaryDelta ?? 0;
                  if (dy > 8 && _drawerController.value < 0.05) {
                    // Swipe down on home screen → expand notifications
                    LauncherService.expandNotifications();
                    return;
                  }
                  _onVerticalDragUpdate(details);
                },
                onVerticalDragEnd: _onVerticalDragEnd,
                child: HomeScreen(
                  key: _homeScreenKey,
                  prefs: widget.prefs,
                  appCache: widget.appCache,
                  notifications: _notifications,
                  onSettingsChanged: () {},
                  onDragStarted: _onDragStarted,
                  onDragEnded: _onDragEnded,
                  onDiscoverOpen: _openDiscover,
                  onDiscoverClose: _closeDiscover,
                ),
              ),
            ),

            // ── App Drawer (finger-tracking slide) ─────────────────
            Transform.translate(
              offset: Offset(0, drawerOffsetY),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onDrawerDragStart,
                onVerticalDragUpdate: _onDrawerDragUpdate,
                onVerticalDragEnd: _onDrawerDragEnd,
                child: SizedBox(
                  height: screenHeight,
                  child: AppDrawer(
                    notifications: _notifications,
                    onClose: _closeDrawer,
                    scrollController: _drawerScrollController,
                    onDragStarted: _onDragStarted,
                    onDragEnded: _onDragEnded,
                  ),
                ),
              ),
            ),

            // ── Drag Bubble: shows when dragging an app ─────────────
            if (_isDragging && _draggingPackage != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 24,
                right: 24,
                child: _DragBubble(
                  packageName: _draggingPackage!,
                  onDragEnded: _onDragEnded,
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

// ─── Drag Bubble ─────────────────────────────────────────────────────────────

class _DragBubble extends StatelessWidget {
  final String packageName;
  final VoidCallback onDragEnded;

  const _DragBubble({required this.packageName, required this.onDragEnded});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: const BoxDecoration(color: Colors.transparent),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // App Info drop target
          DragTarget<Map<String, dynamic>>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (_) {
              LauncherService.openAppInfo(packageName);
              onDragEnded();
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return _BubbleAction(
                icon: Icons.info_outline_rounded,
                label: 'App Info',
                color: isHovered ? cs.onPrimaryContainer : cs.primary,
                backgroundColor: isHovered
                    ? cs.primaryContainer
                    : Colors.transparent,
                onTap: () {
                  LauncherService.openAppInfo(packageName);
                  onDragEnded();
                },
              );
            },
          ),
          Container(width: 1, height: 40, color: cs.outlineVariant),
          // Uninstall drop target
          DragTarget<Map<String, dynamic>>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (_) {
              LauncherService.uninstallApp(packageName);
              onDragEnded();
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return _BubbleAction(
                icon: Icons.delete_outline_rounded,
                label: 'Uninstall',
                color: isHovered ? Colors.white : Colors.red.shade400,
                backgroundColor: isHovered
                    ? Colors.red.shade400
                    : Colors.transparent,
                onTap: () {
                  LauncherService.uninstallApp(packageName);
                  onDragEnded();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BubbleAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _BubbleAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
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
