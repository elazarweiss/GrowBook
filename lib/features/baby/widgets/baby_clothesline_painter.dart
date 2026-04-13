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
    _drawTicks(canvas);
    _drawPhaseLabels(canvas);
    _drawCurrentSlot(canvas);
  }

  void _drawTicks(Canvas canvas) {
    for (final slot in slots) {
      final double x = BabyTimelineUtils.xForSlot(slot, slots);
      final bool isMajor = _isMajorTick(slot);
      final double tickH = isMajor ? 10.0 : 5.0;

      canvas.drawLine(
        Offset(x, lineY),
        Offset(x, lineY + tickH),
        Paint()
          ..color = AppColors.divider
          ..strokeWidth = isMajor ? 1.5 : 1.0
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
    final phases = [
      ('NEWBORN', BabyAgeKind.week, 0, AppColors.babyBlush),
      ('INFANT', BabyAgeKind.month, 3, AppColors.babyMint),
      ('TODDLER', BabyAgeKind.year, 2, AppColors.babySunrise),
    ];

    for (final (label, kind, value, color) in phases) {
      final slot = slots.where((s) => s.kind == kind && s.value == value).firstOrNull;
      if (slot == null) continue;
      final x = BabyTimelineUtils.xForSlot(slot, slots);
      _drawText(
        canvas,
        label,
        Offset(x - 4, lineY - 52),
        TextStyle(
          fontSize: 8,
          color: color.withOpacity(0.80),
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
        ),
      );
    }
  }

  void _drawCurrentSlot(Canvas canvas) {
    final double x = BabyTimelineUtils.xForSlot(currentSlot, slots);

    // Clean accent ring — stroke only, no fill
    canvas.drawCircle(
      Offset(x, lineY),
      20,
      Paint()
        ..color = AppColors.sageGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Small accent dot at center
    canvas.drawCircle(
      Offset(x, lineY),
      3,
      Paint()..color = AppColors.sageGreen,
    );
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
