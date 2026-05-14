import 'dart:async';
import 'dart:ui';
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
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _drawerExtent = 0.0;

  // Discover page animation
  late final AnimationController _discoverController;
  late final Animation<double> _discoverAnimation;

  // Drag bubble state
  String? _draggingPackage;
  bool _isDragging = false;

  // Default launcher banner
  bool _isDefaultLauncher = true;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDefaultLauncher();

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
    _sheetController.dispose();
    _discoverController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutQuart,
      );
    }
  }

  void _closeDrawer() {
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInQuart,
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Home Screen (with synchronized translate/fade)
          AnimatedBuilder(
            animation: _discoverAnimation,
            builder: (context, child) {
              final screenWidth = MediaQuery.of(context).size.width;
              final screenHeight = MediaQuery.of(context).size.height;
              final discoverExtent = _discoverAnimation.value;
              return Transform.translate(
                offset: Offset(
                  screenWidth * 0.25 * discoverExtent,
                  -screenHeight * 0.25 * _drawerExtent,
                ),
                child: Opacity(
                  opacity: ((1.0 - _drawerExtent) * (1.0 - discoverExtent * 0.7)).clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                final dy = details.primaryDelta ?? 0;
                if (dy < -8) {
                  _openDrawer();
                } else if (dy > 8) {
                  LauncherService.expandNotifications();
                }
              },
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

          // 3. App Drawer as DraggableScrollableSheet
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              setState(() {
                _drawerExtent = notification.extent;
              });
              return true;
            },
            child: DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.0,
              minChildSize: 0.0,
              maxChildSize: 1.0,
              snap: true,
              snapSizes: const [0.0, 1.0],
              snapAnimationDuration: const Duration(milliseconds: 320),
              shouldCloseOnMinExtent: false,
              builder: (context, scrollController) {
                return AppDrawer(
                  notifications: _notifications,
                  onClose: _closeDrawer,
                  scrollController: scrollController,
                  onDragStarted: _onDragStarted,
                  onDragEnded: _onDragEnded,
                );
              },
            ),
          ),

          // 4. Drag Bubble — App Info / Delete overlay while dragging
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

          // 5. Default Launcher Banner
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

// ─── Drag Bubble ────────────────────────────────────────────────────────────

class _DragBubble extends StatelessWidget {
  final String packageName;
  final VoidCallback onDragEnded;

  const _DragBubble({required this.packageName, required this.onDragEnded});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // App Info button
          _BubbleAction(
            icon: Icons.info_outline_rounded,
            label: 'App Info',
            color: Theme.of(context).colorScheme.primary,
            onTap: () {
              LauncherService.openAppInfo(packageName);
              onDragEnded();
            },
          ),
          Container(
            width: 1,
            height: 40,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          // Delete button
          _BubbleAction(
            icon: Icons.delete_outline_rounded,
            label: 'Uninstall',
            color: Colors.red.shade400,
            onTap: () {
              LauncherService.uninstallApp(packageName);
              onDragEnded();
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
  final VoidCallback onTap;

  const _BubbleAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

// ─── Default Launcher Banner ────────────────────────────────────────────────

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
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
