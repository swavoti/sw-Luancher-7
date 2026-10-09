import 'dart:ui';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/screens/workspace.dart';
import 'package:swavoti/screens/edit_icons_page.dart';
import 'package:swavoti/screens/home_settings.dart';
import 'package:swavoti/screens/wallpaper_page.dart';
import 'package:swavoti/screens/welcome_screen.dart';
import 'package:swavoti/services/app_database_service.dart';
import 'package:swavoti/services/lightweight_mode.dart';

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
  SharedPreferences.getInstance().then((prefs) {
    LightweightMode.apply(
      prefs.getBool(LightweightMode.preferenceKey) ?? false,
    );
    runApp(const SwavotiApp());
  });
}

class SwavotiApp extends StatefulWidget {
  const SwavotiApp({super.key});

  @override
  State<SwavotiApp> createState() => _SwavotiAppState();
}

class _SwavotiAppState extends State<SwavotiApp> with WidgetsBindingObserver {
  SharedPreferences? _prefs;
  bool _welcomeCompleted = false;
  Map<String, AppInfo> _appCache = {};
  ColorScheme? _lightDynamicColor;
  ColorScheme? _darkDynamicColor;
  final GlobalKey<WorkspaceState> _workspaceKey = GlobalKey<WorkspaceState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      LightweightMode.apply(
        prefs.getBool(LightweightMode.preferenceKey) ?? false,
      );
      final savedPack = prefs.getString('icon_pack') ?? '';
      if (AppDatabaseService.currentIconPack != savedPack) {
        AppDatabaseService.currentIconPack = savedPack;
        await AppDatabaseService.clearIconCache();
        if (mounted) setState(() {});
      }
      try {
        final palette = await DynamicColorPlugin.getCorePalette();
        if (mounted && palette != null) {
          setState(() {
            _lightDynamicColor = palette.toColorScheme().harmonized();
            _darkDynamicColor = palette
                .toColorScheme(brightness: Brightness.dark)
                .harmonized();
          });
        }
      } on Exception catch (error) {
        debugPrint('Could not refresh dynamic colors: $error');
      }
    }
  }

  void _refreshAfterSettingsChanged() {
    final prefs = _prefs;
    if (prefs != null) {
      LightweightMode.apply(
        prefs.getBool(LightweightMode.preferenceKey) ?? false,
      );
    }
    _workspaceKey.currentState?.refreshLauncherSettings();
    setState(() {});
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    // Native OS OOM signal handler
    debugPrint('OS Memory Pressure Received! Dropping caches...');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    AppDatabaseService.clearMemoryIconCache();
    _workspaceKey.currentState?.clearTransientMemoryCaches();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Paint a transparent frame FIRST (0ms), then load data in the background.
  /// This is the Nova technique: never block the first frame for I/O.
  Future<void> _hydrate() async {
    // SharedPreferences is already warm from the pre-runApp call in main().
    final prefs = await SharedPreferences.getInstance();
    LightweightMode.apply(
      prefs.getBool(LightweightMode.preferenceKey) ?? false,
    );
    AppDatabaseService.currentIconPack = prefs.getString('icon_pack') ?? "";

    // Show the UI immediately with whatever we have.
    final welcomeCompleted = prefs.getBool('welcome_completed') ?? false;
    if (mounted) {
      setState(() {
        _prefs = prefs;
        _welcomeCompleted = welcomeCompleted;
      });
    }
    if (!welcomeCompleted) return;

    // Load app metadata and fresh sync concurrently — both happen off-frame.
    final cachedApps = await AppDatabaseService.getAppMetadata();
    final appCache = {for (final app in cachedApps) app.packageName: app};

    if (mounted) setState(() => _appCache = appCache);
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

        lightDynamic = _lightDynamicColor ?? lightDynamic;
        darkDynamic = _darkDynamicColor ?? darkDynamic;
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
          navigatorObservers: [UnfocusOnPageCloseObserver()],
          routes: {
            '/settings': (context) =>
                HomeSettings(onSettingsChanged: _refreshAfterSettingsChanged),
            '/wallpaper': (context) => const WallpaperPage(),
            '/edit_icons': (context) => EditIconsPage(
              backgroundWallpaperPath: '',
              onSettingsApplied: () async {
                await _workspaceKey.currentState?.refreshLauncherSettings();
              },
            ),
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
          themeAnimationDuration: const Duration(milliseconds: 400),
          themeAnimationCurve: Curves.easeInOutCubicEmphasized,
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
          home: _welcomeCompleted
              ? PopScope(
                  canPop: false,
                  child: Workspace(
                    key: _workspaceKey,
                    prefs: prefs,
                    appCache: _appCache,
                  ),
                )
              : WelcomeScreen(
                  onFinished: (enabled) {
                    LightweightMode.apply(enabled);
                    setState(() => _welcomeCompleted = true);
                  },
                ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class UnfocusOnPageCloseObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus?.hasFocus ?? false) focus!.unfocus();
    });
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
