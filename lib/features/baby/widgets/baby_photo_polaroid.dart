import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  bool get _isAbove => slot.index.isOdd;

  double get _tiltRadians {
    final seed = slot.index * 17 + 7;
    return (math.sin(seed.toDouble()) * 2.0) * (math.pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    const double cardW = 88;
    const double photoH = 80;
    const double captionH = 20;
    const double totalH = photoH + captionH + 8;
    const double stemH = 16;

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
      width: 1.5,
      height: 16,
      color: AppColors.divider,
    );
  }

  Widget _buildCard(double cardW, double photoH, double captionH) {
    return Container(
      width: cardW,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: cardW - 8,
                height: photoH,
                child: photoPath != null
                    ? _buildImage(cardW, photoH)
                    : _placeholder(cardW, photoH),
              ),
            ),
          ),
          SizedBox(
            height: captionH,
            child: Center(
              child: Text(
                caption?.isNotEmpty == true ? caption! : slot.label,
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontStyle: FontStyle.italic,
                  color: AppColors.warmTaupe,
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

  Widget _buildImage(double cardW, double photoH) {
    final path = photoPath!;

    if (kIsWeb || path.startsWith('data:')) {
      // Base64 data URL
      final comma = path.indexOf(',');
      if (comma != -1) {
        final bytes = base64Decode(path.substring(comma + 1));
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: cardW - 8,
          height: photoH,
          errorBuilder: (_, __, ___) => _placeholder(cardW, photoH),
        );
      }
      return _placeholder(cardW, photoH);
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: cardW - 8,
      height: photoH,
      errorBuilder: (_, __, ___) => _placeholder(cardW, photoH),
    );
  }

  Widget _placeholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      color: AppColors.accentSoft,
      child: const Center(
        child: Icon(
          Icons.add,
          size: 24,
          color: AppColors.sageGreen,
        ),
      ),
    );
  }
}
