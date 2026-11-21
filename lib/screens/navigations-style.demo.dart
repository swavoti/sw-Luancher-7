import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:swavoti/services/navigation_settings_service.dart';

/// Live animated demo of every close-app / return-to-home animation style.
///
/// Uses [CloseAppAnimationSpec] directly from [NavigationSettingsService] so
/// durations, curves, scale, translation, blur sigma, and icon-anchor origin
/// match the real launcher 1:1.
class NavigationsStyleDemoScreen extends StatefulWidget {
  final CloseAppAnimationStyle? initialStyle;
  final bool initialBlurOverride;

  const NavigationsStyleDemoScreen({
    super.key,
    this.initialStyle,
    this.initialBlurOverride = false,
  });

  @override
  State<NavigationsStyleDemoScreen> createState() =>
      _NavigationsStyleDemoScreenState();
}

class _NavigationsStyleDemoScreenState extends State<NavigationsStyleDemoScreen>
    with TickerProviderStateMixin {
  late CloseAppAnimationStyle _selectedStyle;
  late bool _simulateReturnBlur;
  bool _autoLoop = true;

  // Phase 1: Mock app is open, user swipes up to close (0.0 -> 1.0)
  // Phase 2: Home entrance animation runs with exact CloseAppAnimationSpec
  late final AnimationController _appCloseController;
  late final AnimationController _homeEnterController;
  Timer? _loopTimer;

  // Target icon normalized alignment on the mock phone screen (row 1, col 2)
  static const Alignment _demoIconAnchor = Alignment(0.32, -0.18);

  @override
  void initState() {
    super.initState();
    _selectedStyle =
        widget.initialStyle ?? NavigationSettingsService.instance.style;
    _simulateReturnBlur = widget.initialBlurOverride ||
        NavigationSettingsService.instance.returnBlurEnabled;

    _appCloseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0.0,
    );
    _homeEnterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
      value: 1.0,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playDemoCycle();
    });
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _appCloseController.dispose();
    _homeEnterController.dispose();
    super.dispose();
  }

  CloseAppAnimationSpec get _spec =>
      CloseAppAnimationSpec.forStyle(_selectedStyle);

  double get _effectiveBlurSigma {
    if (_spec.beginBlurSigma > 0) return _spec.beginBlurSigma;
    return _simulateReturnBlur ? 12.0 : 0.0;
  }

  Future<void> _playDemoCycle() async {
    _loopTimer?.cancel();
    if (!mounted) return;

    final spec = _spec;
    _homeEnterController.duration = spec.duration == Duration.zero
        ? const Duration(milliseconds: 1)
        : spec.duration;

    // Reset to "app open" state
    _appCloseController.value = 0.0;
    _homeEnterController.value = 0.0;

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    // Simulate user swiping up to close the app
    await _appCloseController.forward(from: 0.0);
    if (!mounted) return;

    // Trigger exact home entrance spec (mirrors onHomeEnter in HomeScreen)
    if (spec.duration == Duration.zero) {
      _homeEnterController.value = 1.0;
    } else {
      await _homeEnterController.forward(from: 0.0);
    }

    if (!mounted) return;
    if (_autoLoop) {
      _loopTimer = Timer(const Duration(milliseconds: 1300), _playDemoCycle);
    }
  }

  Future<void> _applySelectedStyle() async {
    await NavigationSettingsService.instance.setStyle(_selectedStyle);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied "${_spec.title}"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop(_selectedStyle);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = _spec;
    final blurSigma = _effectiveBlurSigma;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Close-App Animation Demo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _autoLoop ? 'Pause loop' : 'Auto-loop',
            icon: Icon(
              _autoLoop ? Icons.repeat_on_rounded : Icons.repeat_rounded,
            ),
            onPressed: () {
              setState(() => _autoLoop = !_autoLoop);
              if (_autoLoop) {
                _playDemoCycle();
              } else {
                _loopTimer?.cancel();
              }
            },
          ),
          IconButton(
            tooltip: 'Replay now',
            icon: const Icon(Icons.replay_rounded),
            onPressed: _playDemoCycle,
          ),
        ],
      ),
      body: Column(
        children: [
          // Live phone preview
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: AspectRatio(
                  aspectRatio: 9 / 18.5,
                  child: _buildPhoneMockup(cs, spec, blurSigma),
                ),
              ),
            ),
          ),

          // Spec badge bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          spec.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: spec.isExperimental
                              ? cs.tertiaryContainer
                              : cs.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          spec.badge,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: spec.isExperimental
                                ? cs.onTertiaryContainer
                                : cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${spec.duration.inMilliseconds}ms • '
                    'scale ${spec.beginScale.toStringAsFixed(2)}→1.00 • '
                    'opacity ${spec.beginOpacity.toStringAsFixed(2)}→1.00'
                    '${spec.beginOffsetY != 0 ? ' • rise ${spec.beginOffsetY.toInt()}px' : ''}'
                    '${blurSigma > 0 ? ' • blur ${blurSigma.toInt()}px' : ''}'
                    '${spec.usesIconAnchor ? ' • icon-anchored' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Style selector strip
          SizedBox(
            height: 82,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemCount: CloseAppAnimationSpec.all.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = CloseAppAnimationSpec.all[index];
                final selected = item.style == _selectedStyle;
                return ChoiceChip(
                  selected: selected,
                  label: Text(item.title),
                  onSelected: (_) {
                    setState(() => _selectedStyle = item.style);
                    _playDemoCycle();
                  },
                );
              },
            ),
          ),

          // Bottom action bar
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _playDemoCycle,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Replay'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _applySelectedStyle,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Use This Style'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneMockup(
    ColorScheme cs,
    CloseAppAnimationSpec spec,
    double blurSigma,
  ) {
    final curvedEnter = CurvedAnimation(
      parent: _homeEnterController,
      curve: spec.curve,
    );
    final fadeAnim = Tween<double>(
      begin: spec.beginOpacity,
      end: 1.0,
    ).animate(curvedEnter);
    final scaleAnim = Tween<double>(
      begin: spec.beginScale,
      end: 1.0,
    ).animate(curvedEnter);
    final offsetAnim = Tween<double>(
      begin: spec.beginOffsetY,
      end: 0.0,
    ).animate(curvedEnter);
    final blurAnim = Tween<double>(
      begin: blurSigma,
      end: 0.0,
    ).animate(curvedEnter);

    final closeCurved = CurvedAnimation(
      parent: _appCloseController,
      curve: Curves.easeInCubic,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.55),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Persistent wallpaper layer
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1A237E),
                    Color(0xFF3949AB),
                    Color(0xFF00838F),
                  ],
                ),
              ),
            ),

            // Home screen layer driven by exact CloseAppAnimationSpec
            AnimatedBuilder(
              animation: _homeEnterController,
              builder: (context, child) {
                Widget current = child!;
                final blur = blurAnim.value;
                if (blur > 0.05) {
                  current = ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: current,
                  );
                }
                return Opacity(
                  opacity: fadeAnim.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, offsetAnim.value),
                    child: Transform.scale(
                      scale: scaleAnim.value,
                      alignment: spec.usesIconAnchor
                          ? _demoIconAnchor
                          : Alignment.center,
                      child: current,
                    ),
                  ),
                );
              },
              child: _buildMockHomeWorkspace(),
            ),

            // Closing app window overlay (swipe-up to dismiss)
            AnimatedBuilder(
              animation: _appCloseController,
              builder: (context, child) {
                final t = closeCurved.value;
                if (t >= 0.999) return const SizedBox.shrink();
                return Opacity(
                  opacity: (1.0 - t).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -140 * t),
                    child: Transform.scale(
                      scale: 1.0 - (0.28 * t),
                      child: child,
                    ),
                  ),
                );
              },
              child: _buildMockOpenApp(cs),
            ),

            // Gesture pill indicator at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(
                child: Container(
                  width: 64,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMockHomeWorkspace() {
    final colors = [
      Colors.amber,
      Colors.lightBlueAccent,
      Colors.pinkAccent,
      Colors.greenAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
      Colors.tealAccent,
      Colors.cyanAccent,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 24),
      child: Column(
        children: [
          // Mock clock / weather header
          const Text(
            '09:41',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w300,
            ),
          ),
          const Text(
            '22° • Clear',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          // 4x2 app grid (row 0 col 2 highlighted as target icon)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 8,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final isTarget = index == 2;
              return Container(
                decoration: BoxDecoration(
                  color: colors[index].withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: isTarget
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
                child: Icon(
                  isTarget ? Icons.public_rounded : Icons.apps_rounded,
                  color: Colors.black87,
                  size: 18,
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          // Mock dock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                4,
                (i) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockOpenApp(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.pinkAccent.withValues(alpha: 0.85),
                child: const Icon(
                  Icons.public_rounded,
                  size: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Open App Window',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  'Swiping up to close…',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
