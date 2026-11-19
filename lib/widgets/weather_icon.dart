import 'package:flutter/material.dart';
import 'dart:math' as math;

class WeatherIcon extends StatelessWidget {
  final int weatherCode;
  final double size;
  final bool isNight;

  const WeatherIcon({
    super.key,
    required this.weatherCode,
    this.size = 64.0,
    this.isNight = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: WeatherIconPainter(weatherCode, isNight: isNight),
      ),
    );
  }
}

class WeatherIconPainter extends CustomPainter {
  final int code;
  final bool isNight;

  WeatherIconPainter(this.code, {this.isNight = false});

  @override
  void paint(Canvas canvas, Size size) {
    // WMO Weather interpretation codes
    if (code == 0 || code == 1) {
      if (isNight) {
        _drawMoon(canvas, size);
      } else {
        _drawSun(canvas, size);
      }
      if (code == 1) {
        _drawCloud(canvas, size, offset: const Offset(10, 10), scale: 0.7);
      }
    } else if (code == 2 || code == 3) {
      _drawCloud(canvas, size, offset: const Offset(5, 5));
      _drawCloud(
        canvas,
        size,
        offset: const Offset(-5, -5),
        scale: 0.8,
        color: Colors.grey.shade400,
      );
    } else if (code >= 51 && code <= 67 || code >= 80 && code <= 82) {
      _drawCloud(canvas, size, offset: const Offset(0, -5));
      _drawRain(canvas, size);
    } else if (code >= 71 && code <= 77 || code == 85 || code == 86) {
      _drawCloud(canvas, size, offset: const Offset(0, -5));
      _drawSnow(canvas, size);
    } else if (code >= 95) {
      _drawCloud(canvas, size, offset: const Offset(0, -10));
      _drawLightning(canvas, size);
    } else {
      // Default to partly cloudy for unknown codes like fog
      _drawSun(canvas, size);
      _drawCloud(canvas, size, offset: const Offset(10, 10), scale: 0.7);
    }
  }

  void _drawMoon(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3.2;
    // Use saveLayer so BlendMode.clear carves the crescent correctly
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    // Full moon
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFE8E060)
        ..style = PaintingStyle.fill,
    );
    // Carve out crescent
    canvas.drawCircle(
      Offset(center.dx + radius * 0.5, center.dy - radius * 0.2),
      radius * 0.82,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  void _drawSun(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 4;

    canvas.drawCircle(center, radius, paint);

    // Draw rays
    final rayPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = size.width / 16
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final angle = i * (math.pi / 4);
      final p1 = Offset(
        center.dx + math.cos(angle) * (radius * 1.3),
        center.dy + math.sin(angle) * (radius * 1.3),
      );
      final p2 = Offset(
        center.dx + math.cos(angle) * (radius * 1.8),
        center.dy + math.sin(angle) * (radius * 1.8),
      );
      canvas.drawLine(p1, p2, rayPaint);
    }
  }

  void _drawCloud(
    Canvas canvas,
    Size size, {
    Offset offset = Offset.zero,
    double scale = 1.0,
    Color color = Colors.white,
  }) {
    canvas.save();
    canvas.translate(size.width / 2 + offset.dx, size.height / 2 + offset.dy);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // A simple cloud path
    final path = Path();
    final cw = size.width;
    final ch = size.height;

    path.addOval(
      Rect.fromCircle(center: Offset(cw * 0.5, ch * 0.6), radius: cw * 0.25),
    );
    path.addOval(
      Rect.fromCircle(center: Offset(cw * 0.35, ch * 0.65), radius: cw * 0.2),
    );
    path.addOval(
      Rect.fromCircle(center: Offset(cw * 0.7, ch * 0.65), radius: cw * 0.18),
    );
    path.addRect(Rect.fromLTRB(cw * 0.35, ch * 0.55, cw * 0.7, ch * 0.85));

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawRain(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = size.width / 20
      ..strokeCap = StrokeCap.round;

    final cw = size.width;
    final ch = size.height;

    // Draw 3 slanted rain drops
    canvas.drawLine(
      Offset(cw * 0.3, ch * 0.7),
      Offset(cw * 0.25, ch * 0.9),
      paint,
    );
    canvas.drawLine(
      Offset(cw * 0.5, ch * 0.75),
      Offset(cw * 0.45, ch * 0.95),
      paint,
    );
    canvas.drawLine(
      Offset(cw * 0.7, ch * 0.7),
      Offset(cw * 0.65, ch * 0.9),
      paint,
    );
  }

  void _drawSnow(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width / 24
      ..strokeCap = StrokeCap.round;

    final cw = size.width;
    final ch = size.height;

    _drawSnowflake(canvas, Offset(cw * 0.3, ch * 0.8), cw * 0.1, paint);
    _drawSnowflake(canvas, Offset(cw * 0.6, ch * 0.9), cw * 0.12, paint);
    _drawSnowflake(canvas, Offset(cw * 0.8, ch * 0.75), cw * 0.08, paint);
  }

  void _drawSnowflake(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    for (int i = 0; i < 6; i++) {
      final angle = i * (math.pi / 3);
      final p2 = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, p2, paint);
    }
  }

  void _drawLightning(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    final path = Path();
    final cw = size.width;
    final ch = size.height;

    path.moveTo(cw * 0.6, ch * 0.5);
    path.lineTo(cw * 0.35, ch * 0.75);
    path.lineTo(cw * 0.5, ch * 0.75);
    path.lineTo(cw * 0.45, ch * 0.95);
    path.lineTo(cw * 0.7, ch * 0.65);
    path.lineTo(cw * 0.55, ch * 0.65);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
