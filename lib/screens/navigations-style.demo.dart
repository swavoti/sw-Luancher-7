import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:swavoti/services/navigation_settings_service.dart';

/// Live animated demo of every close-app / return-to-home animation style.
///
/// Styled to match [GestureDemoPage] and driven directly by
/// [CloseAppAnimationSpec] so durations, curves, scale, translation,
/// blur sigma, and icon-anchor origin match [HomeScreen] 1:1.
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

  late final AnimationController _appCloseController;
  late final AnimationController _homeEnterController;
  Timer? _loopTimer;

  // Target icon alignment on the simulated 4x3 home grid (row 1, col 2)
  static const Alignment _demoIconAnchor = Alignment(0.32, 0.12);

  @override
  void initState() {
    super.initState();
    _selectedStyle =
        widget.initialStyle ?? NavigationSettingsService.instance.style;
    _simulateReturnBlur = widget.initialBlurOverride ||
        NavigationSettingsService.instance.returnBlurEnabled;

    _appCloseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 0.0,
    );
    _homeEnterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
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

    _appCloseController.value = 0.0;
    _homeEnterController.value = 0.0;

    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;

    await _appCloseController.forward(from: 0.0);
    if (!mounted) return;

    if (spec.duration == Duration.zero) {
      _homeEnterController.value = 1.0;
    } else {
      await _homeEnterController.forward(from: 0.0);
    }

    if (!mounted) return;
    if (_autoLoop) {
      _loopTimer = Timer(const Duration(milliseconds: 1200), _playDemoCycle);
    }
  }

  Future<void> _applySelectedStyle() async {
    await NavigationSettingsService.instance.setStyle(_selectedStyle);
    if (!mounted) return;
    Navigator.of(context).pop(_selectedStyle);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = _spec;
    final blurSigma = _effectiveBlurSigma;
    final selectedIndex = CloseAppAnimationSpec.all.indexWhere(
      (s) => s.style == _selectedStyle,
    );

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar matching GestureDemoPage: indicator dots + Loop/Close
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Row(
                    children: List.generate(CloseAppAnimationSpec.all.length, (
                      i,
                    ) {
                      final active = i == selectedIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.only(right: 6),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _autoLoop ? 'Pause loop' : 'Auto-loop',
                    icon: Icon(
                      _autoLoop
                          ? Icons.repeat_on_rounded
                          : Icons.repeat_rounded,
                      size: 20,
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
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),

            // Header matching GestureDemoPage
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Align(
                      key: ValueKey('title_${spec.id}'),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        spec.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Align(
                      key: ValueKey('desc_${spec.id}_$blurSigma'),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${spec.subtitle} '
                        '(${spec.duration.inMilliseconds}ms'
                        '${blurSigma > 0 ? ', ${blurSigma.toInt()}px blur' : ''})',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Simulated Sandbox Stage matching GestureDemoPage
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _buildSandboxStage(cs, spec, blurSigma),
              ),
            ),

            // Style picker chips
            SizedBox(
              height: 52,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: CloseAppAnimationSpec.all.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
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

            // Bottom action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _playDemoCycle,
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const Text('Replay'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _applySelectedStyle,
                      child: const Text('Apply Style'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSandboxStage(
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
      curve: Curves.easeOutCubic,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            // Background: Simulated Material You Home Grid driven by exact spec
            Positioned.fill(
              child: AnimatedBuilder(
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
                child: _buildSimulatedHomeBackdrop(cs, spec.usesIconAnchor),
              ),
            ),

            // Foreground: Simulated Placeholder App Window closing upward
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _appCloseController,
                builder: (context, child) {
                  final t = closeCurved.value;
                  if (t >= 0.999) return const SizedBox.shrink();
                  return Opacity(
                    opacity: (1.0 - t).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -140 * t),
                      child: Transform.scale(
                        scale: 1.0 - (0.35 * t),
                        alignment: Alignment.center,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _buildPlaceholderApp(cs),
              ),
            ),

            // Simulated Gesture Pill Bar at bottom (matches GestureDemoPage)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: Container(
                  width: 110,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulatedHomeBackdrop(ColorScheme cs, bool highlightTarget) {
    return Container(
      color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
      child: Column(
        children: [
          const Spacer(),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(12, (index) {
              final isTarget = highlightTarget && index == 6;
              return Container(
                decoration: BoxDecoration(
                  color: isTarget
                      ? cs.primaryContainer
                      : cs.surfaceContainerHigh,
                  shape: BoxShape.circle,
                  border: isTarget
                      ? Border.all(color: cs.primary, width: 2)
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderApp(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 130,
            height: 16,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            height: 130,
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < 3; i++) ...[
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 10,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
