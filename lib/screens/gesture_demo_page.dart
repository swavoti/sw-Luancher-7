import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _GestureStep { home, back, recents, complete }

class GestureDemoPage extends StatefulWidget {
  const GestureDemoPage({super.key});

  @override
  State<GestureDemoPage> createState() => _GestureDemoPageState();
}

class _GestureDemoPageState extends State<GestureDemoPage>
    with TickerProviderStateMixin {
  _GestureStep _step = _GestureStep.home;
  bool _stepSucceeded = false;

  // Interactive drag state
  Offset _dragOffset = Offset.zero;
  bool _isDraggingBottom = false;
  bool _isDraggingEdge = false;
  bool _edgeFromLeft = true;
  bool _recentsTriggered = false;
  Timer? _recentsHoldTimer;

  late final AnimationController _hintController;

  @override
  void initState() {
    super.initState();
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _recentsHoldTimer?.cancel();
    _hintController.dispose();
    super.dispose();
  }

  void _completeCurrentStep() {
    if (_stepSucceeded) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _stepSucceeded = true;
    });
    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      setState(() {
        _stepSucceeded = false;
        _dragOffset = Offset.zero;
        _isDraggingBottom = false;
        _isDraggingEdge = false;
        _recentsTriggered = false;
        switch (_step) {
          case _GestureStep.home:
            _step = _GestureStep.back;
          case _GestureStep.back:
            _step = _GestureStep.recents;
          case _GestureStep.recents:
            _step = _GestureStep.complete;
          case _GestureStep.complete:
            break;
        }
      });
    });
  }

  void _restartDemo() {
    _recentsHoldTimer?.cancel();
    setState(() {
      _step = _GestureStep.home;
      _stepSucceeded = false;
      _dragOffset = Offset.zero;
      _isDraggingBottom = false;
      _isDraggingEdge = false;
      _recentsTriggered = false;
    });
  }

  void _closeDemo() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      SystemNavigator.pop();
    }
  }

  String get _title {
    switch (_step) {
      case _GestureStep.home:
        return 'Go Home';
      case _GestureStep.back:
        return 'Go Back';
      case _GestureStep.recents:
        return 'Switch apps';
      case _GestureStep.complete:
        return 'You\'re all set!';
    }
  }

  String get _instruction {
    if (_stepSucceeded) {
      return 'Great job!';
    }
    switch (_step) {
      case _GestureStep.home:
        return 'Swipe up from the bottom of the screen to close this app and return Home.';
      case _GestureStep.back:
        return 'Swipe inward from either the left or right edge to go back.';
      case _GestureStep.recents:
        return 'Swipe up from the bottom, hold briefly, then release to view recent apps.';
      case _GestureStep.complete:
        return 'You\'ve practiced all gesture navigation controls.';
    }
  }

  int get _stepIndex => _step.index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: step dots + Skip
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Row(
                    children: List.generate(3, (i) {
                      final active = i == _stepIndex.clamp(0, 2);
                      final done = _stepIndex > i;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.only(right: 6),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: (active || done)
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _closeDemo,
                    child: Text(_step == _GestureStep.complete ? 'Done' : 'Skip'),
                  ),
                ],
              ),
            ),

            // Instruction Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Align(
                      key: ValueKey('title_${_step.name}_$_stepSucceeded'),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _title,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Align(
                      key: ValueKey('desc_${_step.name}_$_stepSucceeded'),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _instruction,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _stepSucceeded ? cs.primary : cs.onSurfaceVariant,
                          fontWeight:
                              _stepSucceeded ? FontWeight.w600 : FontWeight.w400,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Simulated Interactive Phone Sandbox
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _buildSandboxStage(cs, screenSize),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSandboxStage(ColorScheme cs, Size screenSize) {
    if (_step == _GestureStep.complete) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 40,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Gesture navigation ready',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _restartDemo,
                  child: const Text('Try again'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _closeDemo,
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Compute live scale / translation for placeholder app card
    final upProgress = (-_dragOffset.dy / 160.0).clamp(0.0, 1.0);
    final edgeProgress = (_dragOffset.dx.abs() / 120.0).clamp(0.0, 1.0);

    final double cardScale = _stepSucceeded && _step == _GestureStep.home
        ? 0.25
        : _recentsTriggered
            ? 0.58
            : _isDraggingBottom
                ? (1.0 - upProgress * 0.38)
                : _isDraggingEdge
                    ? (1.0 - edgeProgress * 0.08)
                    : 1.0;

    final Offset cardOffset = _stepSucceeded && _step == _GestureStep.home
        ? const Offset(0, -140)
        : _isDraggingBottom
            ? Offset(_dragOffset.dx * 0.4, _dragOffset.dy * 0.55)
            : Offset.zero;

    final double cardOpacity = _stepSucceeded && _step == _GestureStep.home
        ? 0.0
        : 1.0;

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
            // Background: Simulated Blank Placeholder Home Grid / Recents
            Positioned.fill(
              child: _recentsTriggered
                  ? _buildSimulatedRecentsBackdrop(cs)
                  : _buildSimulatedHomeBackdrop(cs),
            ),

            // Foreground: Simulated Placeholder App Screen
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: cardOpacity,
                child: AnimatedContainer(
                  duration: (_isDraggingBottom || _isDraggingEdge)
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.identity()
                    ..translateByDouble(cardOffset.dx, cardOffset.dy, 0, 1)
                    ..scaleByDouble(cardScale, cardScale, 1, 1),
                  transformAlignment: Alignment.center,
                  child: _buildPlaceholderApp(cs),
                ),
              ),
            ),

            // Success badge overlay
            if (_stepSucceeded)
              Positioned.fill(
                child: Container(
                  color: cs.surface.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: cs.onPrimaryContainer,
                      size: 36,
                    ),
                  ),
                ),
              ),

            // Animated visual cue (finger / pill guide)
            if (!_isDraggingBottom && !_isDraggingEdge && !_stepSucceeded)
              _buildGestureVisualHint(cs),

            // Interactive Bottom Gesture Zone (Home + Recents)
            if (_step == _GestureStep.home || _step == _GestureStep.recents)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 110,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (_) {
                    _recentsHoldTimer?.cancel();
                    setState(() {
                      _isDraggingBottom = true;
                      _dragOffset = Offset.zero;
                      _recentsTriggered = false;
                    });
                  },
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _dragOffset += details.delta;
                    });
                    if (_step == _GestureStep.recents &&
                        -_dragOffset.dy > 70 &&
                        !_recentsTriggered) {
                      _recentsHoldTimer?.cancel();
                      _recentsHoldTimer = Timer(
                        const Duration(milliseconds: 240),
                        () {
                          if (!mounted || !_isDraggingBottom) return;
                          HapticFeedback.selectionClick();
                          setState(() => _recentsTriggered = true);
                        },
                      );
                    }
                  },
                  onVerticalDragEnd: (details) {
                    _recentsHoldTimer?.cancel();
                    final dy = -_dragOffset.dy;
                    final velocity = -(details.primaryVelocity ?? 0);

                    if (_step == _GestureStep.home &&
                        (dy > 80 || velocity > 450)) {
                      _completeCurrentStep();
                    } else if (_step == _GestureStep.recents &&
                        (_recentsTriggered || dy > 110)) {
                      _completeCurrentStep();
                    } else {
                      setState(() {
                        _isDraggingBottom = false;
                        _dragOffset = Offset.zero;
                        _recentsTriggered = false;
                      });
                    }
                  },
                ),
              ),

            // Interactive Left & Right Edge Gesture Zones (Back)
            if (_step == _GestureStep.back) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 64,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) {
                    setState(() {
                      _isDraggingEdge = true;
                      _edgeFromLeft = true;
                      _dragOffset = Offset.zero;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragOffset = Offset(
                        (_dragOffset.dx + details.delta.dx).clamp(0.0, 140.0),
                        _dragOffset.dy + details.delta.dy,
                      );
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    final dx = _dragOffset.dx;
                    final vx = details.primaryVelocity ?? 0;
                    if (dx > 64 || vx > 400) {
                      _completeCurrentStep();
                    } else {
                      setState(() {
                        _isDraggingEdge = false;
                        _dragOffset = Offset.zero;
                      });
                    }
                  },
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 64,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) {
                    setState(() {
                      _isDraggingEdge = true;
                      _edgeFromLeft = false;
                      _dragOffset = Offset.zero;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragOffset = Offset(
                        (_dragOffset.dx + details.delta.dx).clamp(-140.0, 0.0),
                        _dragOffset.dy + details.delta.dy,
                      );
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    final dx = -_dragOffset.dx;
                    final vx = -(details.primaryVelocity ?? 0);
                    if (dx > 64 || vx > 400) {
                      _completeCurrentStep();
                    } else {
                      setState(() {
                        _isDraggingEdge = false;
                        _dragOffset = Offset.zero;
                      });
                    }
                  },
                ),
              ),
            ],

            // Live Back Edge Arrow Indicator
            if (_isDraggingEdge && _step == _GestureStep.back)
              Positioned(
                left: _edgeFromLeft ? 10 : null,
                right: _edgeFromLeft ? null : 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      _edgeFromLeft
                          ? Icons.arrow_forward_rounded
                          : Icons.arrow_back_rounded,
                      color: cs.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                ),
              ),

            // Simulated Gesture Pill Bar at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: Container(
                  width: 96,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderApp(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Blank placeholder app bar
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 130,
                height: 16,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Blank placeholder hero card
          Container(
            width: double.infinity,
            height: 130,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 20),
          // Blank placeholder list items
          for (int i = 0; i < 3; i++) ...[
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

  Widget _buildSimulatedHomeBackdrop(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
      child: Column(
        children: [
          const Spacer(),
          // Blank placeholder home icon grid
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(
              12,
              (_) => Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
              ),
            ),
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

  Widget _buildSimulatedRecentsBackdrop(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerLowest,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 210,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(width: 180),
          Container(
            width: 54,
            height: 210,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGestureVisualHint(ColorScheme cs) {
    return AnimatedBuilder(
      animation: _hintController,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_hintController.value);
        if (_step == _GestureStep.back) {
          // Animated horizontal inward swipe cue on left & right edges
          final shift = 48.0 * t;
          final alpha = (1.0 - t).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned(
                left: 10 + shift,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: alpha,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10 + shift,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Opacity(
                    opacity: alpha,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // Home & Recents upward swipe cue from bottom pill
        final progress = _step == _GestureStep.recents
            ? (t < 0.6 ? (t / 0.6) : 1.0)
            : t;
        final alpha = _step == _GestureStep.recents
            ? (t < 0.85 ? 1.0 : (1.0 - (t - 0.85) / 0.15))
            : (1.0 - t);

        return Positioned(
          left: 0,
          right: 0,
          bottom: 24 + progress * 90,
          child: Center(
            child: Opacity(
              opacity: alpha.clamp(0.0, 1.0),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
