import 'package:flutter/material.dart';
import '../../config/theme.dart';

class MushafPageFrame extends StatelessWidget {
  final Widget child;

  const MushafPageFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.gold, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.gold.withOpacity(0.5), width: 3),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.gold, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class RuledBackground extends StatelessWidget {
  final Widget child;
  final double lineHeight;
  final double offsetTop;

  const RuledBackground({
    super.key,
    required this.child,
    required this.lineHeight,
    this.offsetTop = 0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RuledLinesPainter(
        lineHeight: lineHeight,
        offsetTop: offsetTop,
        color: AppColors.gold.withOpacity(0.15),
      ),
      child: child,
    );
  }
}

class _RuledLinesPainter extends CustomPainter {
  final double lineHeight;
  final double offsetTop;
  final Color color;

  _RuledLinesPainter({
    required this.lineHeight,
    required this.offsetTop,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    for (double y = offsetTop; y < size.height; y += lineHeight) {
      if (y > 0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RuledLinesPainter oldDelegate) =>
      oldDelegate.lineHeight != lineHeight || oldDelegate.offsetTop != offsetTop;
}
