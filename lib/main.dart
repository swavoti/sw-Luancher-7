import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/screens/workspace.dart';
import 'package:swavoti/screens/edit_icons_page.dart';
import 'package:swavoti/screens/home_settings.dart';
import 'package:swavoti/screens/wallpaper_page.dart';
import 'package:swavoti/services/app_database_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash isolation: Prevent Red Screen of Death on widget build failures
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('UI Error caught: ${details.exception}');
    return const SizedBox.shrink(); // Fail silently to keep launcher alive
  };

  // Crash isolation: Catch async unhandled exceptions
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Async Error caught: $error');
    return true; // Prevent app crash
  };

  PaintingBinding.instance.imageCache.maximumSize = 400;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20;

  // Make status bar and navigation bar transparent for edge-to-edge
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Warm up SharedPreferences before runApp so it's already in the instance
  // cache when the widget tree first builds. This eliminates one async round-
  // trip from the hot path and is safe because ensureInitialized() is called
  // above.
  SharedPreferences.getInstance().then((_) => runApp(const SwavotiApp()));
}

class SwavotiApp extends StatefulWidget {
  const SwavotiApp({super.key});

  @override
  State<SwavotiApp> createState() => _SwavotiAppState();
}

class _SwavotiAppState extends State<SwavotiApp> with WidgetsBindingObserver {
  SharedPreferences? _prefs;
  Map<String, AppInfo> _appCache = {};
  Timer? _ramCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrate();
    _startRamChecker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final savedPack = prefs.getString('icon_pack') ?? '';
      if (AppDatabaseService.currentIconPack != savedPack) {
        AppDatabaseService.currentIconPack = savedPack;
        await AppDatabaseService.clearIconCache();
        setState(() {});
      }
    }
  }

  void _startRamChecker() {
    // Background RAM usage checker. Runs every 10 seconds.
    _ramCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      final currentRamMB = ProcessInfo.currentRss / (1024 * 1024);
      
      // If RAM exceeds 150MB, kill the caches and rebuild silently
      if (currentRamMB > 150) {
        debugPrint('RAM Spike Detected: ${currentRamMB.toStringAsFixed(1)} MB. Dropping caches...');
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        
        // Silently rebuild the widget tree to drop detached nodes 
        // without showing any blank screens.
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    // Native OS OOM signal handler
    debugPrint('OS Memory Pressure Received! Dropping caches...');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ramCheckTimer?.cancel();
    super.dispose();
  }

  /// Paint a transparent frame FIRST (0ms), then load data in the background.
  /// This is the Nova technique: never block the first frame for I/O.
  Future<void> _hydrate() async {
    // SharedPreferences is already warm from the pre-runApp call in main().
    final prefs = await SharedPreferences.getInstance();
    AppDatabaseService.currentIconPack = prefs.getString('icon_pack') ?? "";

    // Show the UI immediately with whatever we have.
    if (mounted) setState(() => _prefs = prefs);

    // Load app metadata and fresh sync concurrently — both happen off-frame.
    final cachedApps = await AppDatabaseService.getAppMetadata();
    final appCache = {for (final app in cachedApps) app.packageName: app};

    if (mounted) setState(() => _appCache = appCache);

    // Sync fresh data from OS in background (never blocks paint).
    AppDatabaseService.syncAppsBackground();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    if (prefs == null) {
      return const MaterialApp(
        title: 'Go Launcher 7',
        home: Scaffold(backgroundColor: Colors.transparent),
        debugShowCheckedModeBanner: false,
      );
    }

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        if (lightDynamic != null && darkDynamic != null) {
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized();
        } else {
          // Fallback to default colors
          lightColorScheme = ColorScheme.fromSeed(seedColor: Colors.blue);
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp(
          title: 'Go Launcher 7',
          initialRoute: '/',
          routes: {
            
            '/settings': (context) => const HomeSettings(),
            '/wallpaper': (context) => const WallpaperPage(),
            '/edit_icons': (context) => const EditIconsPage(backgroundWallpaperPath: ''),
          },
          theme: ThemeData(
            colorScheme: lightColorScheme,
            scaffoldBackgroundColor: Colors.transparent,
            useMaterial3: true,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: FadePageTransitionsBuilder(),
                TargetPlatform.iOS: FadePageTransitionsBuilder(),
              },
            ),
          ),
          themeMode: ThemeMode.system,
          darkTheme: ThemeData(
            colorScheme: darkColorScheme,
            scaffoldBackgroundColor: Colors.transparent,
            useMaterial3: true,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: FadePageTransitionsBuilder(),
                TargetPlatform.iOS: FadePageTransitionsBuilder(),
              },
            ),
          ),
          home: PopScope(
            canPop: false,
            child: Workspace(prefs: prefs, appCache: _appCache),
          ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}
