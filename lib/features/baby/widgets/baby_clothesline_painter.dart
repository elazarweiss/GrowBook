import 'package:flutter/material.dart';
import '../../../core/models/baby_slot_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/baby_timeline_utils.dart';

class BabyClotheslinePainter extends CustomPainter {
  final List<BabySlot> slots;
  final BabySlot currentSlot;
  final double lineY;

  const BabyClotheslinePainter({
    required this.slots,
    required this.currentSlot,
    required this.lineY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawTicks(canvas);
    _drawPhaseLabels(canvas);
    _drawCurrentSlot(canvas);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Very faint gradient tint — same approach as ClotheslinePainter
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFE8B4B8).withOpacity(0.06),
            const Color(0xFF93C9BD).withOpacity(0.06),
            const Color(0xFFE8C87A).withOpacity(0.06),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(bgRect),
    );
  }

  void _drawTicks(Canvas canvas) {
    for (final slot in slots) {
      final double x = BabyTimelineUtils.xForSlot(slot, slots);
      final bool isMajor = _isMajorTick(slot);
      final double tickH = isMajor ? 8.0 : 4.0;
      final double opacity = isMajor ? 0.30 : 0.12;

      canvas.drawLine(
        Offset(x, lineY),
        Offset(x, lineY + tickH),
        Paint()
          ..color = AppColors.warmBrown.withOpacity(opacity)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  bool _isMajorTick(BabySlot slot) {
    switch (slot.kind) {
      case BabyAgeKind.week:
        return slot.value % 4 == 0;
      case BabyAgeKind.month:
        return slot.value % 3 == 0;
      case BabyAgeKind.year:
        return true;
    }
  }

  void _drawPhaseLabels(Canvas canvas) {
    // Find the first slot of each phase and draw a label above the wire
    final phases = [
      ('NEWBORN', BabyAgeKind.week, 0, const Color(0xFFE8B4B8)),
      ('INFANT', BabyAgeKind.month, 3, const Color(0xFF93C9BD)),
      ('TODDLER', BabyAgeKind.year, 2, const Color(0xFFE8C87A)),
    ];

    for (final (label, kind, value, color) in phases) {
      final slot = slots.where((s) => s.kind == kind && s.value == value).firstOrNull;
      if (slot == null) continue;
      final x = BabyTimelineUtils.xForSlot(slot, slots);
      _drawText(
        canvas,
        label,
        Offset(x - 4, lineY - 56),
        TextStyle(
          fontSize: 8,
          color: color.withOpacity(0.85),
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      );
    }
  }

  void _drawCurrentSlot(Canvas canvas) {
    final double x = BabyTimelineUtils.xForSlot(currentSlot, slots);

    // Outer glow ring
    canvas.drawCircle(
      Offset(x, lineY), 22,
      Paint()..color = const Color(0xFFE8B4B8).withOpacity(0.35),
    );
    // Inner filled circle
    canvas.drawCircle(
      Offset(x, lineY), 14,
      Paint()..color = const Color(0xFFE8B4B8),
    );

    // Draw a small heart ♥ using a path
    _drawHeart(canvas, Offset(x, lineY), 7, Colors.white);
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Color color) {
    final path = Path();
    // Simple heart approximation
    final x = center.dx;
    final y = center.dy;
    path.moveTo(x, y + size * 0.3);
    path.cubicTo(x, y - size * 0.2, x - size, y - size * 0.4,
        x - size * 0.8, y + size * 0.15);
    path.cubicTo(x - size * 0.6, y + size * 0.6, x, y + size * 0.9,
        x, y + size * 0.3);
    path.moveTo(x, y + size * 0.3);
    path.cubicTo(x, y - size * 0.2, x + size, y - size * 0.4,
        x + size * 0.8, y + size * 0.15);
    path.cubicTo(x + size * 0.6, y + size * 0.6, x, y + size * 0.9,
        x, y + size * 0.3);

    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawText(Canvas canvas, String text, Offset anchor, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, anchor);
  }

  @override
  bool shouldRepaint(BabyClotheslinePainter old) =>
      old.currentSlot.key != currentSlot.key ||
      old.slots.length != slots.length ||
      old.lineY != lineY;
}

