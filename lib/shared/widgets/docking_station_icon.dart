import 'package:flutter/material.dart';

class DockingStationIcon extends StatelessWidget {
  const DockingStationIcon({
    required this.color,
    this.width = 22,
    this.height = 20,
    super.key,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: DockingStationIconPainter(color: color),
    );
  }
}

class DockingStationIconPainter extends CustomPainter {
  const DockingStationIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;

    path
      ..moveTo(size.width * 0.13, size.height * 0.94)
      ..quadraticBezierTo(
        size.width * 0.10,
        size.height * 0.94,
        size.width * 0.10,
        size.height * 0.90,
      )
      ..lineTo(size.width * 0.10, size.height * 0.80)
      ..quadraticBezierTo(
        size.width * 0.10,
        size.height * 0.76,
        size.width * 0.13,
        size.height * 0.76,
      )
      ..lineTo(size.width * 0.27, size.height * 0.76)
      ..quadraticBezierTo(
        size.width * 0.31,
        size.height * 0.75,
        size.width * 0.31,
        size.height * 0.67,
      )
      ..lineTo(size.width * 0.31, size.height * 0.24)
      ..cubicTo(
        size.width * 0.31,
        size.height * 0.11,
        size.width * 0.39,
        size.height * 0.04,
        size.width * 0.50,
        size.height * 0.04,
      )
      ..cubicTo(
        size.width * 0.61,
        size.height * 0.04,
        size.width * 0.69,
        size.height * 0.11,
        size.width * 0.69,
        size.height * 0.24,
      )
      ..lineTo(size.width * 0.69, size.height * 0.67)
      ..quadraticBezierTo(
        size.width * 0.69,
        size.height * 0.75,
        size.width * 0.73,
        size.height * 0.76,
      )
      ..lineTo(size.width * 0.87, size.height * 0.76)
      ..quadraticBezierTo(
        size.width * 0.90,
        size.height * 0.76,
        size.width * 0.90,
        size.height * 0.80,
      )
      ..lineTo(size.width * 0.90, size.height * 0.90)
      ..quadraticBezierTo(
        size.width * 0.90,
        size.height * 0.94,
        size.width * 0.87,
        size.height * 0.94,
      )
      ..close();

    path
      ..moveTo(size.width * 0.44, size.height * 0.70)
      ..lineTo(size.width * 0.44, size.height * 0.31)
      ..quadraticBezierTo(
        size.width * 0.44,
        size.height * 0.23,
        size.width * 0.50,
        size.height * 0.23,
      )
      ..quadraticBezierTo(
        size.width * 0.56,
        size.height * 0.23,
        size.width * 0.56,
        size.height * 0.31,
      )
      ..lineTo(size.width * 0.56, size.height * 0.70)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant DockingStationIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
