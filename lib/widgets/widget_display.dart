import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          lineColor: Colors.white.withValues(alpha: 0.16),
          cellHighlightColor: cs.primary.withValues(alpha: 0.10),
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

    const dashLen = 5.0;
    const gapLen = 5.0;

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

/// Lawnchair / AOSP Launcher3 4-edge interactive widget resize frame with
/// unrestricted width & height handles, live `spanX × spanY` pill, and
/// floating action bar (Configure, Reset Size, Remove, Done).
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
    final threshold = stepSize * 0.48;

    while (_dragAccum >= threshold) {
      final applied = widget.onResizeStep?.call(edge, 1) ?? false;
      if (!applied) {
        _dragAccum = threshold * 0.4;
        break;
      }
      HapticFeedback.selectionClick();
      _dragAccum -= stepSize;
    }

    while (_dragAccum <= -threshold) {
      final applied = widget.onResizeStep?.call(edge, -1) ?? false;
      if (!applied) {
        _dragAccum = -threshold * 0.4;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: widget.child),

        // Clean exterior outline border (positioned outside widget bounds)
        Positioned(
          left: -4,
          top: -4,
          right: -4,
          bottom: -4,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: cs.primary,
                  width: 2.0,
                ),
              ),
            ),
          ),
        ),

        // Remove 'X' button on top-right of outline
        Positioned(
          top: -16,
          right: -16,
          child: Material(
            color: cs.error,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onRemove,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: cs.onError,
                ),
              ),
            ),
          ),
        ),

        // Live Span Dimension Pill Badge (e.g. "2 × 2") & Done check
        Positioned(
          bottom: -16,
          right: -10,
          child: GestureDetector(
            onTap: widget.onExitEdit,
            child: Material(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(14),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.item.spanX} × ${widget.item.spanY}',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: cs.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // TOP Edge Handle
        Positioned(
          top: -16,
          left: 0,
          right: 0,
          height: 34,
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
                width: 64,
                height: 34,
                child: Center(
                  child: _EdgePillVisual(
                    horizontal: true,
                    active: _activeEdge == WidgetResizeEdge.top,
                  ),
                ),
              ),
            ),
          ),
        ),

        // BOTTOM Edge Handle
        Positioned(
          bottom: -16,
          left: 0,
          right: 0,
          height: 34,
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
                width: 64,
                height: 34,
                child: Center(
                  child: _EdgePillVisual(
                    horizontal: true,
                    active: _activeEdge == WidgetResizeEdge.bottom,
                  ),
                ),
              ),
            ),
          ),
        ),

        // LEFT Edge Handle
        Positioned(
          left: -16,
          top: 0,
          bottom: 0,
          width: 34,
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
                width: 34,
                height: 64,
                child: Center(
                  child: _EdgePillVisual(
                    horizontal: false,
                    active: _activeEdge == WidgetResizeEdge.left,
                  ),
                ),
              ),
            ),
          ),
        ),

        // RIGHT Edge Handle
        Positioned(
          right: -16,
          top: 0,
          bottom: 0,
          width: 34,
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
                width: 34,
                height: 64,
                child: Center(
                  child: _EdgePillVisual(
                    horizontal: false,
                    active: _activeEdge == WidgetResizeEdge.right,
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

class _EdgePillVisual extends StatelessWidget {
  final bool horizontal;
  final bool active;

  const _EdgePillVisual({required this.horizontal, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mainLen = active ? 34.0 : 28.0;
    final crossLen = active ? 13.0 : 11.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      width: horizontal ? mainLen : crossLen,
      height: horizontal ? crossLen : mainLen,
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: active ? 0.55 : 0.32),
            blurRadius: active ? 10 : 5,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: horizontal ? 10 : 3,
          height: horizontal ? 3 : 10,
          decoration: BoxDecoration(
            color: cs.onPrimary.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
