import 'package:flutter/material.dart';
import '../../core/theme/app_typography.dart';

class SerifText extends StatelessWidget {
  final String text;
  final double? fontSize;
  final Color? color;
  final TextAlign? textAlign;

  const SerifText(
    this.text, {
    super.key,
    this.fontSize,
    this.color,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    var style = AppTypography.heading2;
    if (fontSize != null || color != null) {
      style = style.copyWith(fontSize: fontSize, color: color);
    }
    return Text(text, style: style, textAlign: textAlign);
  }
}
