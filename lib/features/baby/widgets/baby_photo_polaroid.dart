import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/baby_slot_model.dart';
import '../../../data/baby_data.dart';

/// Layout descriptor for a single photo position within a slot.
class PolaroidLayout {
  final double xOffset;   // horizontal shift from slot center (px)
  final double yFactor;   // 0.0–1.0 how far into the half (1.0 = max)
  final bool isAbove;     // true = above wire, false = below

  const PolaroidLayout(this.xOffset, this.yFactor, this.isAbove);
}

class BabyPhotoPolaroid extends StatelessWidget {
  final BabySlot slot;
  final String? photoPath;       // null → placeholder / ghost
  final String? caption;
  final int photoCount;          // total photos in this entry (for +N badge)
  final VoidCallback onTap;
  final double x;
  final double lineY;
  final double canvasH;

  // Exhibition layout params
  final int photoIndex;          // 0, 1, or 2
  final double xOffset;          // px shift from slot center
  final double yFactor;          // 0.0–1.0 depth into half
  final bool? isAboveOverride;   // null = auto (odd index = above)
  final double sizeFactor;       // 1.0 = normal, 0.82 = slightly smaller
  final BabyMilestoneInfo? milestone; // non-null → ghost card shows emoji

  static const List<PolaroidLayout> layouts = [
    PolaroidLayout(-25.0, 0.85, true),   // photo 0: left, high above
    PolaroidLayout( 30.0, 0.80, false),  // photo 1: right, far below
    PolaroidLayout( 55.0, 0.60, true),   // photo 2: far right, mid-above
  ];

  const BabyPhotoPolaroid({
    super.key,
    required this.slot,
    required this.photoPath,
    required this.caption,
    required this.photoCount,
    required this.onTap,
    required this.x,
    required this.lineY,
    required this.canvasH,
    this.photoIndex = 0,
    this.xOffset = 0,
    this.yFactor = 0.85,
    this.isAboveOverride,
    this.sizeFactor = 1.0,
    this.milestone,
  });

  bool get _isAbove => isAboveOverride ?? slot.index.isOdd;

  /// Consistent tilt seeded by slot index + photo index.
  double get _tiltRadians {
    final seed = slot.index * 17 + photoIndex * 7;
    return (math.sin(seed.toDouble()) * 2.0) * (math.pi / 180);
  }

  String get _displayCaption {
    if (caption?.isNotEmpty == true) return caption!;
    if (milestone != null) return '${milestone!.emoji} ${milestone!.label}';
    return _slotLabel(slot);
  }

  static String _slotLabel(BabySlot slot) {
    final m = kMilestonesBySlot[slot.key];
    if (m != null) return '${m.emoji} ${m.label}';
    switch (slot.kind) {
      case BabyAgeKind.week:
        return 'Week ${slot.value}';
      case BabyAgeKind.month:
        return '${slot.value} months';
      case BabyAgeKind.year:
        return '${slot.value} year${slot.value == 1 ? '' : 's'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    const double stemH = 16;
    const double captionH = 20;

    final double halfH = _isAbove ? lineY : (canvasH - lineY);
    final double maxCardH = halfH * yFactor - stemH - captionH;
    final double cardH = (maxCardH * sizeFactor).clamp(50.0, 190.0);
    final double cardW = (cardH * 0.82 * sizeFactor).clamp(45.0, 155.0);

    final double centerX = x + xOffset;
    final double top = _isAbove
        ? lineY - stemH - cardH - captionH
        : lineY + stemH;
    final double left = centerX - cardW / 2;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: onTap,
        child: Transform.rotate(
          angle: _tiltRadians,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isAbove) ...[
                _buildCard(context, cardW, cardH, captionH),
                _buildStem(stemH),
              ] else ...[
                _buildStem(stemH),
                _buildCard(context, cardW, cardH, captionH),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStem(double h) => Container(
        width: 1.5,
        height: h,
        color: AppColors.divider,
      );

  Widget _buildCard(BuildContext context, double cardW, double cardH, double captionH) {
    final isGhost = photoPath == null && milestone != null;

    return Container(
      width: cardW,
      decoration: BoxDecoration(
        color: isGhost ? AppColors.background : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isGhost
            ? Border.all(
                color: AppColors.sageGreen.withOpacity(0.45),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
        boxShadow: isGhost
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: cardW - 10,
                    height: cardH,
                    child: isGhost
                        ? _ghostContent(cardW, cardH)
                        : (photoPath != null
                            ? _buildImage(cardW, cardH)
                            : _placeholder(cardW, cardH)),
                  ),
                ),
                // "+N" badge when there are more than 3 photos and this is the 3rd
                if (photoIndex == 2 && photoCount > 3)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${photoCount - 3}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: captionH,
            child: Center(
              child: Text(
                _displayCaption,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontStyle: FontStyle.italic,
                  color: isGhost
                      ? AppColors.sageGreen.withOpacity(0.7)
                      : AppColors.warmTaupe,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ghostContent(double w, double h) {
    return Container(
      color: AppColors.sageGreen.withOpacity(0.06),
      child: Center(
        child: Text(
          milestone?.emoji ?? '📸',
          style: TextStyle(fontSize: (h * 0.35).clamp(18.0, 42.0)),
        ),
      ),
    );
  }

  Widget _buildImage(double cardW, double cardH) {
    final path = photoPath!;
    if (path.startsWith('data:')) {
      final comma = path.indexOf(',');
      if (comma == -1) return _placeholder(cardW, cardH);
      return Image.memory(
        base64Decode(path.substring(comma + 1)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(cardW, cardH),
      );
    }
    if (path.startsWith('server:')) {
      return Image.network(
        'http://localhost:7272/photo?path=${Uri.encodeComponent(path.substring(7))}',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(cardW, cardH),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(cardW, cardH),
    );
  }

  Widget _placeholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      color: AppColors.accentSoft,
      child: const Center(
        child: Icon(Icons.add, size: 28, color: AppColors.sageGreen),
      ),
    );
  }
}
