import 'package:flutter/material.dart';

class CheckeredFlagStrip extends StatelessWidget {
  const CheckeredFlagStrip({this.height = 6, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CheckeredFlagPainter(
          dark: const Color(0xFF111827),
          light: Colors.white,
          accent: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

class _CheckeredFlagPainter extends CustomPainter {
  const _CheckeredFlagPainter({
    required this.dark,
    required this.light,
    required this.accent,
  });

  final Color dark;
  final Color light;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final square = size.height;
    final paint = Paint();
    var column = 0;
    for (var x = 0.0; x < size.width; x += square) {
      paint.color = column.isEven ? dark : light;
      canvas.drawRect(Rect.fromLTWH(x, 0, square, size.height), paint);
      column++;
    }
    paint.color = accent.withValues(alpha: 0.62);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), paint);
  }

  @override
  bool shouldRepaint(covariant _CheckeredFlagPainter oldDelegate) {
    return oldDelegate.dark != dark ||
        oldDelegate.light != light ||
        oldDelegate.accent != accent;
  }
}
