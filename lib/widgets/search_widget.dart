import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';

class SearchWidget extends StatefulWidget {
  final VoidCallback onRemove;

  const SearchWidget({super.key, required this.onRemove});

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dark teal/slate background matching the Google Pixel search bar
    final barBg = isDark
        ? const Color(0xFF132024)
        : cs.surfaceContainerHigh;
    final borderColor = isDark
        ? const Color(0xFF263C42)
        : cs.outlineVariant.withValues(alpha: 0.4);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onSearchTap,
          child: Container(
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: barBg,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: borderColor,
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Authentic Google 'G' Logo
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onSearchTap,
                  child: const GoogleGLogo(size: 24),
                ),

                // Center Spacer (Empty pill space matching screenshot)
                const Expanded(
                  child: SizedBox.expand(),
                ),

                // Google Voice Search Mic
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: LauncherService.openGoogleVoiceSearch,
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: GoogleMicLogo(size: 21),
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // Google Lens Camera
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: LauncherService.openGoogleLens,
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: GoogleLensLogo(size: 22),
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

// ─── Authentic Google 'G' Logo CustomPainter ─────────────────────────────────

class GoogleGLogo extends StatelessWidget {
  final double size;
  const GoogleGLogo({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final paintBlue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paintGreen = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paintYellow = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paintRed = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Blue section (Right arc + horizontal bar)
    final pathBlue = Path()
      ..moveTo(23.745, 12.27)
      ..cubicTo(23.745, 11.57, 23.685, 10.87, 23.555, 10.2)
      ..lineTo(12.0, 10.2)
      ..lineTo(12.0, 14.71)
      ..lineTo(18.6, 14.71)
      ..cubicTo(18.31, 16.23, 17.46, 17.53, 16.2, 18.39)
      ..lineTo(16.2, 21.44)
      ..lineTo(20.08, 21.44)
      ..cubicTo(22.35, 19.35, 23.745, 16.27, 23.745, 12.27)
      ..close();
    canvas.drawPath(pathBlue, paintBlue);

    // Green section (Bottom arc)
    final pathGreen = Path()
      ..moveTo(12.0, 24.0)
      ..cubicTo(15.24, 24.0, 17.95, 22.92, 19.93, 21.09)
      ..lineTo(16.05, 18.04)
      ..cubicTo(14.97, 18.76, 13.6, 19.2, 12.0, 19.2)
      ..cubicTo(8.89, 19.2, 6.26, 17.1, 5.32, 14.27)
      ..lineTo(1.21, 14.27)
      ..lineTo(1.21, 17.42)
      ..cubicTo(3.19, 21.31, 7.29, 24.0, 12.0, 24.0)
      ..close();
    canvas.drawPath(pathGreen, paintGreen);

    // Yellow section (Bottom-left arc)
    final pathYellow = Path()
      ..moveTo(5.32, 14.27)
      ..cubicTo(5.08, 13.55, 4.94, 12.78, 4.94, 12.0)
      ..cubicTo(4.94, 11.22, 5.08, 10.45, 5.32, 9.73)
      ..lineTo(5.32, 6.58)
      ..lineTo(1.21, 6.58)
      ..cubicTo(0.44, 8.11, 0.0, 9.99, 0.0, 12.0)
      ..cubicTo(0.0, 14.01, 0.44, 15.89, 1.21, 17.42)
      ..lineTo(5.32, 14.27)
      ..close();
    canvas.drawPath(pathYellow, paintYellow);

    // Red section (Top arc)
    final pathRed = Path()
      ..moveTo(12.0, 4.75)
      ..cubicTo(13.77, 4.75, 15.35, 5.36, 16.6, 6.55)
      ..lineTo(20.02, 3.13)
      ..cubicTo(17.95, 1.19, 15.24, 0.0, 12.0, 0.0)
      ..cubicTo(7.29, 0.0, 3.19, 2.69, 1.21, 6.58)
      ..lineTo(5.32, 9.73)
      ..cubicTo(6.26, 6.9, 8.89, 4.75, 12.0, 4.75)
      ..close();
    canvas.drawPath(pathRed, paintRed);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Authentic Multi-colored Google Mic CustomPainter ─────────────────────────

class GoogleMicLogo extends StatelessWidget {
  final double size;
  const GoogleMicLogo({super.key, this.size = 21});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleMicPainter(),
    );
  }
}

class _GoogleMicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 1. Blue Capsule Head
    final headRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(8.5, 2.5, 7.0, 11.5),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(headRect, bluePaint);

    // 2. Red Cradle Arc
    final cradleRect = const Rect.fromLTWH(6.0, 7.0, 12.0, 10.0);
    canvas.drawArc(cradleRect, 0.1, pi - 0.2, false, redPaint);

    // 3. Yellow Center Stem
    canvas.drawLine(
      const Offset(12.0, 17.0),
      const Offset(12.0, 20.5),
      yellowPaint,
    );

    // 4. Green Base Foot
    canvas.drawLine(
      const Offset(8.5, 20.5),
      const Offset(15.5, 20.5),
      greenPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Authentic Multi-colored Google Lens CustomPainter ───────────────────────

class GoogleLensLogo extends StatelessWidget {
  final double size;
  const GoogleLensLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLensPainter(),
    );
  }
}

class _GoogleLensPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final strokeWidth = 2.3;

    final blueStroke = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final redStroke = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final yellowStroke = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final greenFill = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final blueFill = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. Blue Top-Left Corner
    final blueCorner = Path()
      ..moveTo(4.0, 9.5)
      ..lineTo(4.0, 7.5)
      ..cubicTo(4.0, 5.5, 5.5, 4.0, 7.5, 4.0)
      ..lineTo(9.5, 4.0);
    canvas.drawPath(blueCorner, blueStroke);

    // 2. Red Top-Right Corner
    final redCorner = Path()
      ..moveTo(14.5, 4.0)
      ..lineTo(16.5, 4.0)
      ..cubicTo(18.5, 4.0, 20.0, 5.5, 20.0, 7.5)
      ..lineTo(20.0, 9.5);
    canvas.drawPath(redCorner, redStroke);

    // 3. Yellow Bottom-Left Corner
    final yellowCorner = Path()
      ..moveTo(4.0, 14.5)
      ..lineTo(4.0, 16.5)
      ..cubicTo(4.0, 18.5, 5.5, 20.0, 7.5, 20.0)
      ..lineTo(9.5, 20.0);
    canvas.drawPath(yellowCorner, yellowStroke);

    // 4. Center Blue Camera Lens Ring
    canvas.drawCircle(const Offset(12.0, 12.0), 3.4, blueStroke);

    // 5. Green Bottom-Right Flash / Shutter Dot
    canvas.drawCircle(const Offset(17.5, 17.5), 1.9, greenFill);

    // Small red dot at top right lens accent
    canvas.drawCircle(const Offset(12.0, 12.0), 1.2, blueFill);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
