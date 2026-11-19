import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';

class SearchWidget extends StatefulWidget {
  final VoidCallback onRemove;

  const SearchWidget({super.key, required this.onRemove});

  static final ValueNotifier<int> configRevision = ValueNotifier<int>(0);
  static bool isVisible = true;
  static String colorVariant = 'surface_high';

  static void syncFromPrefs(SharedPreferences prefs) {
    isVisible = prefs.getBool('show_dock_search_bar') ?? true;
    colorVariant = prefs.getString('search_bar_color_variant') ?? 'surface_high';
  }

  static Future<void> setVisible(bool visible) async {
    isVisible = visible;
    configRevision.value++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_dock_search_bar', visible);
  }

  static Future<void> setColorVariant(String variant) async {
    colorVariant = variant;
    configRevision.value++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('search_bar_color_variant', variant);
  }

  static Color resolveBackgroundColor(ColorScheme cs, String variant) {
    switch (variant) {
      case 'surface_highest':
        return cs.surfaceContainerHighest;
      case 'primary_container':
        return cs.primaryContainer;
      case 'secondary_container':
        return cs.secondaryContainer;
      case 'tertiary_container':
        return cs.tertiaryContainer;
      case 'inverse_surface':
        return cs.inverseSurface;
      case 'surface_high':
      default:
        return cs.surfaceContainerHigh;
    }
  }

  static Color resolveIconColor(ColorScheme cs, String variant) {
    switch (variant) {
      case 'primary_container':
        return cs.onPrimaryContainer;
      case 'secondary_container':
        return cs.onSecondaryContainer;
      case 'tertiary_container':
        return cs.onTertiaryContainer;
      case 'inverse_surface':
        return cs.onInverseSurface;
      case 'surface_highest':
      case 'surface_high':
      default:
        return cs.onSurfaceVariant;
    }
  }

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  String? _browserPackage;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    SearchWidget.syncFromPrefs(prefs);
    if (mounted) {
      setState(() {
        _browserPackage = prefs.getString('search_browser_package');
      });
    }
  }

  void _onSearchTap() {
    LauncherService.openUrlInBrowser(
      'https://www.google.com',
      _browserPackage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<int>(
      valueListenable: SearchWidget.configRevision,
      builder: (context, _, _) {
        final barColor = SearchWidget.resolveBackgroundColor(
          cs,
          SearchWidget.colorVariant,
        );
        final iconColor = SearchWidget.resolveIconColor(
          cs,
          SearchWidget.colorVariant,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onSearchTap,
          child: Container(
            height: 46,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.25),
                width: 1.0,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                // Official Google 'G' Logo (M3 Dynamic Color)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onSearchTap,
                  child: GoogleGLogo(size: 21, color: iconColor),
                ),

                // Center Spacer
                const Expanded(
                  child: SizedBox.expand(),
                ),

                // Official Google Voice Search Mic (M3 Dynamic Color)
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: LauncherService.openGoogleVoiceSearch,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: GoogleMicLogo(size: 20, color: iconColor),
                    ),
                  ),
                ),

                const SizedBox(width: 2),

                // Official Google Lens Camera SVG (M3 Dynamic Color)
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: LauncherService.openGoogleLens,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: GoogleLensLogo(size: 20, color: iconColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Official Google 'G' Logo Vector (M3 Dynamic Tinted) ─────────────────────

class GoogleGLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const GoogleGLogo({super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleGPainter(color: tint),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  final Color color;

  const _GoogleGPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Official 24x24 Google 'G' glyph path
    final path = Path()
      ..moveTo(21.805, 10.042)
      ..lineTo(12.24, 10.042)
      ..lineTo(12.24, 14.088)
      ..lineTo(17.752, 14.088)
      ..cubicTo(17.508, 15.398, 16.758, 16.512, 15.636, 17.256)
      ..cubicTo(14.702, 17.878, 13.524, 18.248, 12.24, 18.248)
      ..cubicTo(9.634, 18.248, 7.428, 16.488, 6.64, 14.122)
      ..cubicTo(6.438, 13.516, 6.324, 12.87, 6.324, 12.2)
      ..cubicTo(6.324, 11.53, 6.438, 10.884, 6.64, 10.278)
      ..cubicTo(7.428, 7.912, 9.634, 6.152, 12.24, 6.152)
      ..cubicTo(13.67, 6.152, 14.952, 6.644, 15.962, 7.606)
      ..lineTo(18.922, 4.646)
      ..cubicTo(17.128, 2.976, 14.896, 1.96, 12.24, 1.96)
      ..cubicTo(8.222, 1.96, 4.748, 4.264, 3.062, 7.624)
      ..cubicTo(2.382, 8.996, 2.0, 10.554, 2.0, 12.2)
      ..cubicTo(2.0, 13.846, 2.382, 15.404, 3.062, 16.776)
      ..cubicTo(4.748, 20.136, 8.222, 22.44, 12.24, 22.44)
      ..cubicTo(15.002, 22.44, 17.318, 21.524, 19.01, 19.96)
      ..cubicTo(20.946, 18.174, 22.04, 15.54, 22.04, 12.42)
      ..cubicTo(22.04, 11.616, 21.958, 10.816, 21.805, 10.042)
      ..close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─── Official Google Mic Vector (M3 Dynamic Tinted) ──────────────────────────

class GoogleMicLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const GoogleMicLogo({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleMicPainter(color: tint),
    );
  }
}

class _GoogleMicPainter extends CustomPainter {
  final Color color;

  const _GoogleMicPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Capsule head
    final headRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(9.0, 2.5, 6.0, 10.5),
      const Radius.circular(3.0),
    );
    canvas.drawRRect(headRect, fillPaint);

    // U-shaped cradle arc
    const cradleRect = Rect.fromLTWH(6.0, 6.2, 12.0, 10.2);
    canvas.drawArc(cradleRect, 0.08, pi - 0.16, false, strokePaint);

    // Vertical stem
    canvas.drawLine(
      const Offset(12.0, 16.6),
      const Offset(12.0, 21.0),
      strokePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleMicPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─── Official Google Lens SVG Vector (M3 Dynamic Tinted) ─────────────────────

class GoogleLensLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const GoogleLensLogo({super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLensPainter(color: tint),
    );
  }
}

class _GoogleLensPainter extends CustomPainter {
  final Color color;

  const _GoogleLensPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Official Google Lens camera frame with top camera bump:
    // Top-left up across top camera bump to top-right
    final topFrame = Path()
      ..moveTo(3.5, 10.0)
      ..lineTo(3.5, 8.2)
      ..cubicTo(3.5, 6.6, 4.8, 5.3, 6.4, 5.3)
      ..lineTo(8.2, 5.3)
      ..lineTo(9.4, 3.6)
      ..cubicTo(9.7, 3.2, 10.1, 3.0, 10.6, 3.0)
      ..lineTo(13.4, 3.0)
      ..cubicTo(13.9, 3.0, 14.3, 3.2, 14.6, 3.6)
      ..lineTo(15.8, 5.3)
      ..lineTo(17.6, 5.3)
      ..cubicTo(19.2, 5.3, 20.5, 6.6, 20.5, 8.2)
      ..lineTo(20.5, 12.2);
    canvas.drawPath(topFrame, strokePaint);

    // Bottom-left rounded corner frame
    final bottomLeft = Path()
      ..moveTo(3.5, 14.2)
      ..lineTo(3.5, 17.1)
      ..cubicTo(3.5, 18.7, 4.8, 20.0, 6.4, 20.0)
      ..lineTo(12.2, 20.0);
    canvas.drawPath(bottomLeft, strokePaint);

    // Center Lens circle (filled)
    canvas.drawCircle(const Offset(12.0, 12.8), 2.7, fillPaint);

    // Bottom-right Google Lens accent dot (filled)
    canvas.drawCircle(const Offset(17.8, 18.0), 1.85, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleLensPainter oldDelegate) =>
      oldDelegate.color != color;
}
