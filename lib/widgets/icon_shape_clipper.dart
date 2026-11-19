import 'package:flutter/material.dart';

/// Wraps any widget (typically an app icon) with the user-selected icon shape clip.
class IconShapeClipper extends StatelessWidget {
  final Widget child;
  final String shape;
  final double size;

  const IconShapeClipper({
    super.key,
    required this.child,
    required this.shape,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    if (shape == 'Circle') {
      return ClipOval(
        child: SizedBox(width: size, height: size, child: child),
      );
    }
    if (shape == 'Squircle') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: SizedBox(width: size, height: size, child: child),
      );
    }
    if (shape == 'Rounded Rectangle') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: SizedBox(width: size, height: size, child: child),
      );
    }
    if (shape == 'Teardrop') {
      final r = Radius.circular(size * 0.5);
      final tip = Radius.circular(size * 0.14);
      return ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: r,
          topRight: r,
          bottomLeft: r,
          bottomRight: tip,
        ),
        child: SizedBox(width: size, height: size, child: child),
      );
    }
    // Default — no clip
    return SizedBox(width: size, height: size, child: child);
  }
}
