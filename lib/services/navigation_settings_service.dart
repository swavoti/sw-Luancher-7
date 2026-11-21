import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';

/// Supported close-app / return-to-home animation styles.
///
/// Both [HomeScreen] and [NavigationsStyleDemoScreen] read directly from
/// [CloseAppAnimationSpec] so the live demo matches real launcher behavior
/// 1:1 in timing, curves, scale, translation, blur, and icon anchor origin.
enum CloseAppAnimationStyle {
  homeSettle,
  iconCoordinationBlur,
  wallpaperDepthZoom,
  swipeUpRise,
  instant,
}

class CloseAppAnimationSpec {
  final CloseAppAnimationStyle style;
  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final bool isExperimental;
  final Duration duration;
  final Curve curve;
  final double beginOpacity;
  final double beginScale;
  final double beginOffsetY;
  final double beginBlurSigma;
  final bool usesIconAnchor;

  const CloseAppAnimationSpec({
    required this.style,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.isExperimental,
    required this.duration,
    required this.curve,
    required this.beginOpacity,
    required this.beginScale,
    required this.beginOffsetY,
    required this.beginBlurSigma,
    required this.usesIconAnchor,
  });

  static const List<CloseAppAnimationSpec> all = [
    CloseAppAnimationSpec(
      style: CloseAppAnimationStyle.homeSettle,
      id: 'home_settle',
      title: 'Default — Home Settle',
      subtitle: '240ms smooth fade & subtle 0.93→1.0 scale settle on return.',
      badge: 'Default',
      isExperimental: false,
      duration: Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      beginOpacity: 0.0,
      beginScale: 0.93,
      beginOffsetY: 0.0,
      beginBlurSigma: 0.0,
      usesIconAnchor: false,
    ),
    CloseAppAnimationSpec(
      style: CloseAppAnimationStyle.iconCoordinationBlur,
      id: 'icon_coordination_blur',
      title: 'Icon Coordination + Blur',
      subtitle:
          'Anchored scale from last launched icon with animated Gaussian blur.',
      badge: 'Experimental',
      isExperimental: true,
      duration: Duration(milliseconds: 260),
      curve: Curves.easeOutExpo,
      beginOpacity: 0.15,
      beginScale: 0.86,
      beginOffsetY: 0.0,
      beginBlurSigma: 14.0,
      usesIconAnchor: true,
    ),
    CloseAppAnimationSpec(
      style: CloseAppAnimationStyle.wallpaperDepthZoom,
      id: 'wallpaper_depth_zoom',
      title: 'Wallpaper Depth Zoom',
      subtitle: 'Zooms down from 1.07→1.0 with fade to match swipe-home depth.',
      badge: 'Experimental',
      isExperimental: true,
      duration: Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      beginOpacity: 0.0,
      beginScale: 1.07,
      beginOffsetY: 0.0,
      beginBlurSigma: 0.0,
      usesIconAnchor: false,
    ),
    CloseAppAnimationSpec(
      style: CloseAppAnimationStyle.swipeUpRise,
      id: 'swipe_up_rise',
      title: 'Swipe-Up Rise',
      subtitle: 'Workspace rises 32px with fade to follow upward gesture flow.',
      badge: 'Experimental',
      isExperimental: true,
      duration: Duration(milliseconds: 220),
      curve: Curves.easeOutQuart,
      beginOpacity: 0.0,
      beginScale: 0.98,
      beginOffsetY: 32.0,
      beginBlurSigma: 0.0,
      usesIconAnchor: false,
    ),
    CloseAppAnimationSpec(
      style: CloseAppAnimationStyle.instant,
      id: 'instant',
      title: 'Instant (No Animation)',
      subtitle: 'Immediate snap to home with zero entrance transition.',
      badge: 'Fast',
      isExperimental: false,
      duration: Duration.zero,
      curve: Curves.linear,
      beginOpacity: 1.0,
      beginScale: 1.0,
      beginOffsetY: 0.0,
      beginBlurSigma: 0.0,
      usesIconAnchor: false,
    ),
  ];

  static CloseAppAnimationSpec forStyle(CloseAppAnimationStyle style) {
    return all.firstWhere(
      (s) => s.style == style,
      orElse: () => all.first,
    );
  }

  static CloseAppAnimationStyle fromId(String? id) {
    for (final s in all) {
      if (s.id == id) return s.style;
    }
    return CloseAppAnimationStyle.homeSettle;
  }
}

class NavigationSettingsService extends ChangeNotifier {
  NavigationSettingsService._();

  static final NavigationSettingsService instance =
      NavigationSettingsService._();

  static const String _keyStyle = 'nav_close_app_style';
  static const String _keyGestureNavContract = 'nav_gesture_nav_contract';
  static const String _keyIconCoordBlur = 'nav_icon_coord_blur';
  static const String _keyReturnBlur = 'nav_return_blur';
  static const String _keyPredictiveBackScale = 'nav_predictive_back_scale';
  static const String _keyKeepLauncherWarm = 'nav_keep_launcher_warm';

  bool _loaded = false;
  CloseAppAnimationStyle _style = CloseAppAnimationStyle.homeSettle;
  bool _gestureNavContractEnabled = false;
  bool _iconCoordinationBlurEnabled = false;
  bool _returnBlurEnabled = false;
  bool _predictiveBackScaleEnabled = false;
  bool _keepLauncherWarmEnabled = true;

  Alignment _lastLaunchAlignment = Alignment.center;

  CloseAppAnimationStyle get style => _style;
  bool get gestureNavContractEnabled => _gestureNavContractEnabled;
  bool get iconCoordinationBlurEnabled => _iconCoordinationBlurEnabled;
  bool get returnBlurEnabled => _returnBlurEnabled;
  bool get predictiveBackScaleEnabled => _predictiveBackScaleEnabled;
  bool get keepLauncherWarmEnabled => _keepLauncherWarmEnabled;
  Alignment get lastLaunchAlignment => _lastLaunchAlignment;

  CloseAppAnimationSpec get effectiveSpec {
    if (_iconCoordinationBlurEnabled &&
        _style == CloseAppAnimationStyle.homeSettle) {
      return CloseAppAnimationSpec.forStyle(
        CloseAppAnimationStyle.iconCoordinationBlur,
      );
    }
    return CloseAppAnimationSpec.forStyle(_style);
  }

  double get effectiveBeginBlurSigma {
    final base = effectiveSpec.beginBlurSigma;
    if (base > 0) return base;
    return _returnBlurEnabled ? 12.0 : 0.0;
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _style = CloseAppAnimationSpec.fromId(prefs.getString(_keyStyle));
    _gestureNavContractEnabled = prefs.getBool(_keyGestureNavContract) ?? false;
    _iconCoordinationBlurEnabled = prefs.getBool(_keyIconCoordBlur) ?? false;
    _returnBlurEnabled = prefs.getBool(_keyReturnBlur) ?? false;
    _predictiveBackScaleEnabled =
        prefs.getBool(_keyPredictiveBackScale) ?? false;
    _keepLauncherWarmEnabled = prefs.getBool(_keyKeepLauncherWarm) ?? true;
    _loaded = true;
    await _syncToNative();
    notifyListeners();
  }

  void recordLaunchOrigin(Rect? sourceBounds, Size screenSize) {
    if (sourceBounds == null ||
        screenSize.width <= 0 ||
        screenSize.height <= 0) {
      _lastLaunchAlignment = Alignment.center;
      return;
    }
    final cx = sourceBounds.center.dx.clamp(0.0, screenSize.width);
    final cy = sourceBounds.center.dy.clamp(0.0, screenSize.height);
    final nx = (cx / screenSize.width) * 2.0 - 1.0;
    final ny = (cy / screenSize.height) * 2.0 - 1.0;
    _lastLaunchAlignment = Alignment(
      nx.clamp(-0.9, 0.9),
      ny.clamp(-0.9, 0.9),
    );
    _syncToNative();
  }

  Future<void> setStyle(CloseAppAnimationStyle value) async {
    _style = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStyle, CloseAppAnimationSpec.forStyle(value).id);
    await _syncToNative();
    notifyListeners();
  }

  Future<void> setGestureNavContractEnabled(bool value) async {
    _gestureNavContractEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGestureNavContract, value);
    await _syncToNative();
    notifyListeners();
  }

  Future<void> setIconCoordinationBlurEnabled(bool value) async {
    _iconCoordinationBlurEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIconCoordBlur, value);
    await _syncToNative();
    notifyListeners();
  }

  Future<void> setReturnBlurEnabled(bool value) async {
    _returnBlurEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReturnBlur, value);
    notifyListeners();
  }

  Future<void> setPredictiveBackScaleEnabled(bool value) async {
    _predictiveBackScaleEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPredictiveBackScale, value);
    notifyListeners();
  }

  Future<void> setKeepLauncherWarmEnabled(bool value) async {
    _keepLauncherWarmEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepLauncherWarm, value);
    await _syncToNative();
    notifyListeners();
  }

  Future<void> _syncToNative() async {
    final spec = effectiveSpec;
    final pivotX = spec.usesIconAnchor
        ? ((_lastLaunchAlignment.x + 1.0) * 0.5).clamp(0.05, 0.95)
        : 0.5;
    final pivotY = spec.usesIconAnchor
        ? ((_lastLaunchAlignment.y + 1.0) * 0.5).clamp(0.05, 0.95)
        : 0.5;
    await LauncherService.syncNavigationSettings(
      gestureNavContractEnabled:
          _gestureNavContractEnabled || _iconCoordinationBlurEnabled,
      keepLauncherWarmEnabled: _keepLauncherWarmEnabled,
      durationMs: spec.duration.inMilliseconds,
      beginAlpha: spec.beginOpacity,
      beginScale: spec.beginScale,
      beginOffsetY: spec.beginOffsetY,
      pivotX: pivotX,
      pivotY: pivotY,
    );
  }
}
