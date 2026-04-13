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
    _drawCurrentSlot(canvas);
  }

  void _drawTicks(Canvas canvas) {
    for (final slot in slots) {
      final double x = BabyTimelineUtils.xForSlot(slot, slots);
      final bool isMajor = _isMajorTick(slot);
      final double tickH = isMajor ? 12.0 : 6.0;

      canvas.drawLine(
        Offset(x, lineY - tickH), // tick goes UP from wire
        Offset(x, lineY),
        Paint()
          ..color = isMajor
              ? AppColors.warmTaupe.withOpacity(0.5)
              : AppColors.divider
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

  void _drawCurrentSlot(Canvas canvas) {
    final double x = BabyTimelineUtils.xForSlot(currentSlot, slots);

    // Accent ring sitting on the wire
    canvas.drawCircle(
      Offset(x, lineY),
      28,
      Paint()
        ..color = AppColors.sageGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    canvas.drawCircle(
      Offset(x, lineY),
      4,
      Paint()..color = AppColors.sageGreen,
    );
  }

  @override
  bool shouldRepaint(BabyClotheslinePainter oldDelegate) =>
      oldDelegate.currentSlot.key != currentSlot.key ||
      oldDelegate.slots.length != slots.length ||
      oldDelegate.lineY != lineY;
}
