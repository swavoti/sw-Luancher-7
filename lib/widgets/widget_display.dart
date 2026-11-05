import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swavoti/screens/search_settings.dart';
import 'package:swavoti/screens/weather_page.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/widgets/search_widget.dart';
import 'package:swavoti/widgets/time_weather_widget.dart';
import 'package:swavoti/widgets/widget_host.dart';

enum WidgetResizeEdge { left, right, top, bottom }

/// Subtle Lawnchair / AOSP Launcher3 grid cell guide overlay displayed while
/// dragging or resizing widgets so side-by-side cell alignment is unmistakable.
class WorkspaceResizeGridOverlay extends StatelessWidget {
  final int columns;
  final int rows;
  final LauncherItem? activeItem;

  const WorkspaceResizeGridOverlay({
    super.key,
    required this.columns,
    required this.rows,
    this.activeItem,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: CustomPaint(
        painter: _WorkspaceGridPainter(
          columns: columns,
          rows: rows,
          lineColor: Colors.white.withValues(alpha: 0.055),
          cellHighlightColor: cs.primary.withValues(alpha: 0.045),
          activeRect: activeItem == null
              ? null
              : (
                  activeItem!.x,
                  activeItem!.y,
                  activeItem!.spanX,
                  activeItem!.spanY,
                ),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WorkspaceGridPainter extends CustomPainter {
  final int columns;
  final int rows;
  final Color lineColor;
  final Color cellHighlightColor;
  final (int, int, int, int)? activeRect;

  const _WorkspaceGridPainter({
    required this.columns,
    required this.rows,
    required this.lineColor,
    required this.cellHighlightColor,
    this.activeRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (columns <= 0 || rows <= 0) return;
    final cellW = size.width / columns;
    final cellH = size.height / rows;

    if (activeRect != null) {
      final (ax, ay, aw, ah) = activeRect!;
      final fillPaint = Paint()
        ..color = cellHighlightColor
        ..style = PaintingStyle.fill;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(ax * cellW + 3, ay * cellH + 3, aw * cellW - 6, ah * cellH - 6),
        const Radius.circular(18),
      );
      canvas.drawRRect(rrect, fillPaint);
    }

    final dashPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const dashLen = 3.0;
    const gapLen = 9.0;

    for (int c = 0; c <= columns; c++) {
      final dx = c * cellW;
      double y = 0;
      while (y < size.height) {
        final endY = (y + dashLen).clamp(0.0, size.height);
        canvas.drawLine(Offset(dx, y), Offset(dx, endY), dashPaint);
        y += dashLen + gapLen;
      }
    }

    for (int r = 0; r <= rows; r++) {
      final dy = r * cellH;
      double x = 0;
      while (x < size.width) {
        final endX = (x + dashLen).clamp(0.0, size.width);
        canvas.drawLine(Offset(x, dy), Offset(endX, dy), dashPaint);
        x += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WorkspaceGridPainter oldDelegate) {
    return oldDelegate.columns != columns ||
        oldDelegate.rows != rows ||
        oldDelegate.activeRect != activeRect ||
        oldDelegate.lineColor != lineColor;
  }
}

/// Renders either an Android AppWidgetHostView (with Dart-Isolate snapshot
/// hibernation on off-screen pages) or a built-in launcher widget.
class WidgetDisplay extends StatelessWidget {
  final LauncherItem item;
  final double cellWidth;
  final double cellHeight;
  final int currentPage;
  final bool isFeedback;
  final bool isEditing;
  final bool suppressInnerPointers;
  final WidgetCapabilities capabilities;
  final VoidCallback onRemove;
  final VoidCallback onExitEdit;
  final VoidCallback onResetSize;
  final bool Function(WidgetResizeEdge edge, int stepDelta)? onResizeStep;
  final VoidCallback? onResizeCommit;
  final VoidCallback? onConfigure;

  const WidgetDisplay({
    super.key,
    required this.item,
    required this.cellWidth,
    required this.cellHeight,
    required this.currentPage,
    required this.onRemove,
    required this.onExitEdit,
    required this.onResetSize,
    this.isFeedback = false,
    this.isEditing = false,
    this.suppressInnerPointers = false,
    this.capabilities = const WidgetCapabilities(),
    this.onResizeStep,
    this.onResizeCommit,
    this.onConfigure,
  });

  @override
  Widget build(BuildContext context) {
    final widthDp = (item.spanX * cellWidth - 8).clamp(28.0, 2000.0);
    final heightDp = (item.spanY * cellHeight - 8).clamp(28.0, 2000.0);

    Widget content;
    if (item.type == 'widget' && item.appWidgetId != null) {
      content = Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: _HostedAndroidWidgetSurface(
          key: ValueKey('hosted_widget_${item.appWidgetId}'),
          appWidgetId: item.appWidgetId!,
          label: item.label,
          itemPage: item.page,
          currentPage: currentPage,
          widthDp: widthDp,
          heightDp: heightDp,
          isFeedback: isFeedback,
        ),
      );
    } else if (item.type == 'search_widget') {
      content = Padding(
        padding: const EdgeInsets.all(4),
        child: SearchWidget(
          key: ValueKey('search_widget_${item.id}'),
          onRemove: onRemove,
        ),
      );
    } else if (item.type == 'time_weather_widget') {
      content = Padding(
        padding: const EdgeInsets.all(2),
        child: TimeWeatherWidget(
          key: ValueKey('time_weather_widget_${item.id}'),
          onRemove: onRemove,
        ),
      );
    } else {
      content = const SizedBox.shrink();
    }

    if (suppressInnerPointers) {
      content = IgnorePointer(child: content);
    }

    if (!isFeedback && isEditing) {
      return Launcher3ResizeFrame(
        item: item,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        capabilities: capabilities,
        onRemove: onRemove,
        onExitEdit: onExitEdit,
        onResetSize: onResetSize,
        onResizeStep: onResizeStep,
        onResizeCommit: onResizeCommit,
        onConfigure: onConfigure,
        child: content,
      );
    }

    return content;
  }
}

class _HostedAndroidWidgetSurface extends StatefulWidget {
  final int appWidgetId;
  final String label;
  final int itemPage;
  final int currentPage;
  final double widthDp;
  final double heightDp;
  final bool isFeedback;

  const _HostedAndroidWidgetSurface({
    super.key,
    required this.appWidgetId,
    required this.label,
    required this.itemPage,
    required this.currentPage,
    required this.widthDp,
    required this.heightDp,
    required this.isFeedback,
  });

  @override
  State<_HostedAndroidWidgetSurface> createState() =>
      _HostedAndroidWidgetSurfaceState();
}

class _HostedAndroidWidgetSurfaceState
    extends State<_HostedAndroidWidgetSurface> {
  late bool _keepLive;
  Timer? _periodicSnapshotTimer;

  @override
  void initState() {
    super.initState();
    _keepLive = !widget.isFeedback &&
        WidgetHostController.instance.shouldMountLiveView(
          itemPage: widget.itemPage,
          currentPage: widget.currentPage,
        );
    if (_keepLive) {
      WidgetHostController.instance.notifyWidgetSizeChanged(
        widget.appWidgetId,
        widthDp: widget.widthDp,
        heightDp: widget.heightDp,
      );
      _scheduleSnapshotWarmup();
    }
  }

  void _scheduleSnapshotWarmup() {
    _periodicSnapshotTimer?.cancel();
    _periodicSnapshotTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || !_keepLive) return;
      unawaited(
        WidgetHostController.instance.captureWidgetSnapshot(widget.appWidgetId),
      );
    });
  }

  @override
  void didUpdateWidget(covariant _HostedAndroidWidgetSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextLive = !widget.isFeedback &&
        WidgetHostController.instance.shouldMountLiveView(
          itemPage: widget.itemPage,
          currentPage: widget.currentPage,
        );

    if (_keepLive && !nextLive) {
      // Capture an Isolate-compressed snapshot right before hibernating the AndroidView
      WidgetHostController.instance
          .captureWidgetSnapshot(widget.appWidgetId)
          .whenComplete(() {
            if (!mounted) return;
            final stillOffscreen = !WidgetHostController.instance
                .shouldMountLiveView(
                  itemPage: widget.itemPage,
                  currentPage: widget.currentPage,
                );
            if (stillOffscreen && _keepLive) {
              setState(() => _keepLive = false);
            }
          });
    } else if (!_keepLive && nextLive) {
      _keepLive = true;
      WidgetHostController.instance.notifyWidgetSizeChanged(
        widget.appWidgetId,
        widthDp: widget.widthDp,
        heightDp: widget.heightDp,
        immediate: true,
      );
      _scheduleSnapshotWarmup();
    } else if (_keepLive &&
        ((widget.widthDp - oldWidget.widthDp).abs() >= 1.5 ||
            (widget.heightDp - oldWidget.heightDp).abs() >= 1.5)) {
      WidgetHostController.instance.notifyWidgetSizeChanged(
        widget.appWidgetId,
        widthDp: widget.widthDp,
        heightDp: widget.heightDp,
      );
      _scheduleSnapshotWarmup();
    }
  }

  @override
  void dispose() {
    _periodicSnapshotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_keepLive || widget.isFeedback) {
      return ListenableBuilder(
        listenable: WidgetHostController.instance,
        builder: (context, _) {
          final snap = WidgetHostController.instance.getCachedSnapshot(
            widget.appWidgetId,
          );
          final cs = Theme.of(context).colorScheme;
          if (snap != null && snap.isNotEmpty) {
            return Image.memory(
              snap,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            );
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.widgets_rounded,
                      size: 22,
                      color: cs.primary,
                    ),
                    if (widget.label.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return AndroidView(
      viewType: 'widget_view',
      creationParams: <String, dynamic>{
        'appWidgetId': widget.appWidgetId,
        'widthDp': widget.widthDp.round(),
        'heightDp': widget.heightDp.round(),
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

/// Lawnchair / AOSP Launcher3 interactive widget resize frame identical to
/// modern Android (Android 12/13/14+ Material You).
///
/// Features:
/// - Smooth rounded rectangular outline stroke matching widget shape
/// - Circular solid dot handles centered directly on the border stroke midpoints
///   (shown dynamically based on horizontal/vertical resizability)
/// - Material You squircle reconfigure FAB (with pencil icon) positioned at
///   the bottom-right corner for reconfigurable and custom widgets (identical to AOSP)
/// - Generous touch targets for responsive drag gestures
/// - Clean, decluttered design matching stock AOSP Launcher3
class Launcher3ResizeFrame extends StatefulWidget {
  final LauncherItem item;
  final Widget child;
  final double cellWidth;
  final double cellHeight;
  final WidgetCapabilities capabilities;
  final VoidCallback onRemove;
  final VoidCallback onExitEdit;
  final VoidCallback onResetSize;
  final bool Function(WidgetResizeEdge edge, int stepDelta)? onResizeStep;
  final VoidCallback? onResizeCommit;
  final VoidCallback? onConfigure;

  const Launcher3ResizeFrame({
    super.key,
    required this.item,
    required this.child,
    required this.cellWidth,
    required this.cellHeight,
    required this.capabilities,
    required this.onRemove,
    required this.onExitEdit,
    required this.onResetSize,
    this.onResizeStep,
    this.onResizeCommit,
    this.onConfigure,
  });

  @override
  State<Launcher3ResizeFrame> createState() => _Launcher3ResizeFrameState();
}

class _Launcher3ResizeFrameState extends State<Launcher3ResizeFrame> {
  double _dragAccum = 0.0;
  WidgetResizeEdge? _activeEdge;

  void _onEdgeDragStart(WidgetResizeEdge edge) {
    HapticFeedback.lightImpact();
    setState(() {
      _activeEdge = edge;
      _dragAccum = 0.0;
    });
  }

  void _onEdgeDragUpdate(WidgetResizeEdge edge, double primaryDelta) {
    final stepSize =
        (edge == WidgetResizeEdge.left || edge == WidgetResizeEdge.right)
            ? widget.cellWidth
            : widget.cellHeight;
    if (stepSize <= 8) return;

    _dragAccum += primaryDelta;
    final threshold = stepSize * 0.44;

    while (_dragAccum >= threshold) {
      final applied = widget.onResizeStep?.call(edge, 1) ?? false;
      if (!applied) {
        _dragAccum = threshold * 0.35;
        break;
      }
      HapticFeedback.selectionClick();
      _dragAccum -= stepSize;
    }

    while (_dragAccum <= -threshold) {
      final applied = widget.onResizeStep?.call(edge, -1) ?? false;
      if (!applied) {
        _dragAccum = -threshold * 0.35;
        break;
      }
      HapticFeedback.selectionClick();
      _dragAccum += stepSize;
    }
  }

  void _onEdgeDragEnd() {
    if (_activeEdge != null) {
      setState(() {
        _activeEdge = null;
        _dragAccum = 0.0;
      });
    }
    if (widget.item.appWidgetId != null) {
      WidgetHostController.instance.notifyWidgetSizeChanged(
        widget.item.appWidgetId!,
        widthDp: (widget.item.spanX * widget.cellWidth - 8).clamp(28.0, 2000.0),
        heightDp:
            (widget.item.spanY * widget.cellHeight - 8).clamp(28.0, 2000.0),
        immediate: true,
      );
    }
    widget.onResizeCommit?.call();
  }

  void _handleDefaultConfigure(BuildContext context) {
    widget.onExitEdit();
    if (widget.item.type == 'search_widget') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SearchSettingsScreen()),
      );
    } else if (widget.item.type == 'time_weather_widget') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WeatherPage()),
      );
    } else if (widget.item.appWidgetId != null) {
      unawaited(LauncherService.configureWidget(widget.item.appWidgetId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Material You system dynamic accent color
    final accentColor = cs.primary;
    // Contrast check for pen icon
    final penIconColor = accentColor.computeLuminance() > 0.45
        ? const Color(0xFF191C1E)
        : cs.onPrimary;

    // Resizability flags: fallback to both resizable if unconfigured
    final rawCanH = widget.capabilities.resizeHorizontal;
    final rawCanV = widget.capabilities.resizeVertical;
    final canResizeH = rawCanH || (!rawCanH && !rawCanV);
    final canResizeV = rawCanV || (!rawCanH && !rawCanV);

    final showReconfigure = widget.capabilities.configurable ||
        widget.item.type == 'search_widget' ||
        widget.item.type == 'time_weather_widget' ||
        widget.item.appWidgetId != null ||
        widget.onConfigure != null;

    const frameOffset = 10.0;
    const strokeWidth = 2.0;
    const cornerRadius = 24.0;
    const touchTarget = 48.0;

    // Center the touch target directly over the stroke line:
    // stroke line center is at (-frameOffset + strokeWidth / 2) = -9.0.
    const handleTouchOffset = (-frameOffset + strokeWidth / 2) - (touchTarget / 2);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: widget.child),

        // Rounded rectangular outline frame (AOSP Launcher3 widget_resize_frame)
        Positioned(
          left: -frameOffset,
          top: -frameOffset,
          right: -frameOffset,
          bottom: -frameOffset,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cornerRadius),
                border: Border.all(
                  color: accentColor,
                  width: strokeWidth,
                ),
              ),
            ),
          ),
        ),

        // TOP Handle (shown when vertically resizable)
        if (canResizeV)
          Positioned(
            top: handleTouchOffset,
            left: 0,
            right: 0,
            height: touchTarget,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) =>
                    _onEdgeDragStart(WidgetResizeEdge.top),
                onVerticalDragUpdate: (d) =>
                    _onEdgeDragUpdate(WidgetResizeEdge.top, d.primaryDelta ?? 0),
                onVerticalDragEnd: (_) => _onEdgeDragEnd(),
                onVerticalDragCancel: _onEdgeDragEnd,
                child: SizedBox(
                  width: touchTarget,
                  height: touchTarget,
                  child: Center(
                    child: _HandleDot(
                      active: _activeEdge == WidgetResizeEdge.top,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // BOTTOM Handle (shown when vertically resizable)
        if (canResizeV)
          Positioned(
            bottom: handleTouchOffset,
            left: 0,
            right: 0,
            height: touchTarget,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) =>
                    _onEdgeDragStart(WidgetResizeEdge.bottom),
                onVerticalDragUpdate: (d) => _onEdgeDragUpdate(
                  WidgetResizeEdge.bottom,
                  d.primaryDelta ?? 0,
                ),
                onVerticalDragEnd: (_) => _onEdgeDragEnd(),
                onVerticalDragCancel: _onEdgeDragEnd,
                child: SizedBox(
                  width: touchTarget,
                  height: touchTarget,
                  child: Center(
                    child: _HandleDot(
                      active: _activeEdge == WidgetResizeEdge.bottom,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // LEFT Handle (shown when horizontally resizable)
        if (canResizeH)
          Positioned(
            left: handleTouchOffset,
            top: 0,
            bottom: 0,
            width: touchTarget,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) =>
                    _onEdgeDragStart(WidgetResizeEdge.left),
                onHorizontalDragUpdate: (d) =>
                    _onEdgeDragUpdate(WidgetResizeEdge.left, d.primaryDelta ?? 0),
                onHorizontalDragEnd: (_) => _onEdgeDragEnd(),
                onHorizontalDragCancel: _onEdgeDragEnd,
                child: SizedBox(
                  width: touchTarget,
                  height: touchTarget,
                  child: Center(
                    child: _HandleDot(
                      active: _activeEdge == WidgetResizeEdge.left,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // RIGHT Handle (shown when horizontally resizable)
        if (canResizeH)
          Positioned(
            right: handleTouchOffset,
            top: 0,
            bottom: 0,
            width: touchTarget,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) =>
                    _onEdgeDragStart(WidgetResizeEdge.right),
                onHorizontalDragUpdate: (d) => _onEdgeDragUpdate(
                  WidgetResizeEdge.right,
                  d.primaryDelta ?? 0,
                ),
                onHorizontalDragEnd: (_) => _onEdgeDragEnd(),
                onHorizontalDragCancel: _onEdgeDragEnd,
                child: SizedBox(
                  width: touchTarget,
                  height: touchTarget,
                  child: Center(
                    child: _HandleDot(
                      active: _activeEdge == WidgetResizeEdge.right,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // RECONFIGURE BUTTON (The Pen / Pencil FAB at bottom-right corner)
        // Matches AOSP Launcher3 `widget_reconfigure_button`
        if (showReconfigure)
          Positioned(
            right: -6,
            bottom: -6,
            child: Material(
              color: accentColor,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (widget.onConfigure != null) {
                    widget.onConfigure!();
                  } else {
                    _handleDefaultConfigure(context);
                  }
                },
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Icon(
                      Icons.edit_rounded,
                      size: 20,
                      color: penIconColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Circular dot handle matching Launcher3 AOSP resize handles.
class _HandleDot extends StatelessWidget {
  final bool active;
  final Color color;

  const _HandleDot({required this.active, required this.color});

  @override
  Widget build(BuildContext context) {
    final size = active ? 16.0 : 13.5;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: active ? 0.35 : 0.22),
            blurRadius: active ? 6 : 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
