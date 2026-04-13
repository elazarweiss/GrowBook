import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/baby_slot_model.dart';

class BabyPhotoPolaroid extends StatelessWidget {
  final BabySlot slot;
  final String? photoPath;
  final String? caption;
  final VoidCallback onTap;
  final double x;
  final double lineY;

  const BabyPhotoPolaroid({
    super.key,
    required this.slot,
    required this.photoPath,
    required this.caption,
    required this.onTap,
    required this.x,
    required this.lineY,
  });

  /// Odd-indexed slots hang above the wire, even-indexed below.
  bool get _isAbove => slot.index.isOdd;

  /// Pseudo-random tilt ±3° seeded by slot index.
  double get _tiltRadians {
    final seed = slot.index * 17 + 7;
    return (math.sin(seed.toDouble()) * 3.0) * (math.pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    const double cardW = 68;
    const double photoH = 52;
    const double captionH = 18;
    const double totalH = photoH + captionH + 8; // 8 = top+bottom border
    const double stemH = 14;

    // Position: centered on x, hanging above or below the wire
    final double top = _isAbove
        ? lineY - totalH - stemH
        : lineY + stemH;
    final double left = x - cardW / 2;

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
                _buildCard(cardW, photoH, captionH),
                _buildStem(),
              ] else ...[
                _buildStem(),
                _buildCard(cardW, photoH, captionH),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStem() {
    return Container(
      width: 2,
      height: 14,
      color: AppColors.warmTaupe.withOpacity(0.5),
    );
  }

  Widget _buildCard(double cardW, double photoH, double captionH) {
    return Container(
      width: cardW,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: AppColors.warmBrown.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(1, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Photo area
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: SizedBox(
                width: cardW - 8,
                height: photoH,
                child: photoPath != null
                    ? Image.file(
                        File(photoPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(cardW, photoH),
                      )
                    : _placeholder(cardW, photoH),
              ),
            ),
          ),
          // Caption strip
          SizedBox(
            height: captionH,
            child: Center(
              child: Text(
                caption?.isNotEmpty == true ? caption! : slot.label,
                style: const TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 7,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF5C4A32),
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

  Widget _placeholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      color: const Color(0xFFF5F1EB),
      child: Center(
        child: Icon(
          Icons.add_photo_alternate_outlined,
          size: 20,
          color: AppColors.warmTaupe.withOpacity(0.6),
        ),
      ),
    );
  }
}
