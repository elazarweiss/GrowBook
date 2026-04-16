import 'package:flutter/material.dart';
import '../../../core/models/baby_slot_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/baby_timeline_utils.dart';

class BabyClotheslinePainter extends CustomPainter {
  final List<BabySlot> slots;
  final BabySlot currentSlot;
  final double lineY;
  final Set<String> milestoneKeys;

  const BabyClotheslinePainter({
    required this.slots,
    required this.currentSlot,
    required this.lineY,
    this.milestoneKeys = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawTicks(canvas);
    _drawCurrentSlot(canvas);
  }

  void _drawTicks(Canvas canvas) {
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final slot in slots) {
      final double x = BabyTimelineUtils.xForSlot(slot, slots);
      final bool isMilestone = milestoneKeys.contains(slot.key);
      final bool isMajor = _isMajorTick(slot);
      final double tickH = isMilestone ? 18.0 : (isMajor ? 12.0 : 6.0);
      final Color tickColor = isMilestone
          ? AppColors.sageGreen
          : (isMajor
              ? AppColors.warmTaupe.withOpacity(0.5)
              : AppColors.divider);

      // Tick line goes UP from wire
      canvas.drawLine(
        Offset(x, lineY - tickH),
        Offset(x, lineY),
        Paint()
          ..color = tickColor
          ..strokeWidth = isMilestone ? 1.8 : (isMajor ? 1.5 : 1.0)
          ..strokeCap = StrokeCap.round,
      );

      // Milestone dot ON the wire
      if (isMilestone) {
        canvas.drawCircle(
          Offset(x, lineY),
          3.0,
          Paint()..color = AppColors.sageGreen,
        );
      }

      // Label below wire — every 2 weeks (weeks), every 3 months, every year
      if (_shouldShowLabel(slot)) {
        final label = _tickLabel(slot);
        labelPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 8.5,
            color: AppColors.warmTaupe.withOpacity(0.5),
            fontFamily: 'Inter',
          ),
        );
        labelPainter.layout();
        labelPainter.paint(
          canvas,
          Offset(x - labelPainter.width / 2, lineY + 8),
        );
      }
    }
  }

  bool _shouldShowLabel(BabySlot slot) {
    switch (slot.kind) {
      case BabyAgeKind.week:
        return slot.value % 2 == 0;
      case BabyAgeKind.month:
        return slot.value % 3 == 0;
      case BabyAgeKind.year:
        return true;
    }
  }

  String _tickLabel(BabySlot slot) {
    switch (slot.kind) {
      case BabyAgeKind.week:
        return '${slot.value}w';
      case BabyAgeKind.month:
        return '${slot.value}m';
      case BabyAgeKind.year:
        return '${slot.value}y';
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
      oldDelegate.lineY != lineY ||
      oldDelegate.milestoneKeys != milestoneKeys;
}
