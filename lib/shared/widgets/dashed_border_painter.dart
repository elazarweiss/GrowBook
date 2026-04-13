import 'package:flutter/material.dart';

class DashedBorderPainter extends CustomPainter {
  final double borderRadius;
  final Color color;
  final double dashLen;
  final double gapLen;

  const DashedBorderPainter({
    this.borderRadius = 12,
    this.color = const Color(0x80D4B483), // softGold 50%
    this.dashLen = 5,
    this.gapLen = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      Radius.circular(borderRadius),
    );
    final path = Path()..addRRect(rrect);
    final pm = path.computeMetrics().first;
    double dist = 0;
    bool draw = true;
    while (dist < pm.length) {
      final step = draw ? dashLen : gapLen;
      if (draw) {
        canvas.drawPath(pm.extractPath(dist, dist + step), paint);
      }
      dist += step;
      draw = !draw;
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.dashLen != dashLen;
}
