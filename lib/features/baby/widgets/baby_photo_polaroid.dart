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
  final double canvasH;

  const BabyPhotoPolaroid({
    super.key,
    required this.slot,
    required this.photoPath,
    required this.caption,
    required this.onTap,
    required this.x,
    required this.lineY,
    required this.canvasH,
  });

  /// Odd-indexed slots hang above the wire, even-indexed below.
  bool get _isAbove => slot.index.isOdd;

  /// Pseudo-random tilt ±2° seeded by slot index.
  double get _tiltRadians {
    final seed = slot.index * 17 + 7;
    return (math.sin(seed.toDouble()) * 2.0) * (math.pi / 180);
  }

  String get _displayCaption {
    if (caption?.isNotEmpty == true) return caption!;
    return _slotLabel(slot);
  }

  static String _slotLabel(BabySlot slot) {
    switch (slot.kind) {
      case BabyAgeKind.week:
        return slot.value == 0 ? 'Birth' : 'Week ${slot.value}';
      case BabyAgeKind.month:
        return '${slot.value} months';
      case BabyAgeKind.year:
        return '${slot.value} year${slot.value == 1 ? '' : 's'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Card width fits within slot spacing; height fills ~85% of the available
    // half-canvas so polaroids reach close to top/bottom edges.
    const double stemH = 18;
    const double captionH = 22;
    final double halfH = _isAbove ? lineY : (canvasH - lineY);
    final double cardH =
        (halfH - stemH - captionH - 16).clamp(60.0, 320.0); // 16 = margin
    final double cardW = (cardH * 0.82).clamp(60.0, 260.0);

    final double top = _isAbove
        ? lineY - stemH - cardH - captionH
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
                _buildCard(cardW, cardH, captionH),
                _buildStem(stemH),
              ] else ...[
                _buildStem(stemH),
                _buildCard(cardW, cardH, captionH),
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

  Widget _buildCard(double cardW, double cardH, double captionH) {
    return Container(
      width: cardW,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: cardW - 10,
                height: cardH,
                child: photoPath != null
                    ? _buildImage(cardW, cardH)
                    : _placeholder(cardW, cardH),
              ),
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

  Widget _buildImage(double cardW, double cardH) {
    final path = photoPath!;
    if (kIsWeb || path.startsWith('data:')) {
      final comma = path.indexOf(',');
      if (comma != -1) {
        final bytes = base64Decode(path.substring(comma + 1));
        return Image.memory(bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(cardW, cardH));
      }
      return _placeholder(cardW, cardH);
    }
    return Image.file(File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(cardW, cardH));
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
