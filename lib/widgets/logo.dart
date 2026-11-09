import 'package:flutter/material.dart';

/// Learner logotipi: ochiq kitob ustida "tushunish" uchquni.
/// Geometriya 100×100 katakda; `assets/logo.svg` bilan bir xil.
class LearnerLogo extends StatelessWidget {
  const LearnerLogo({super.key, this.size = 42, this.background = true});
  final double size;

  /// false — faqat belgi (kitob va uchqun), fon kvadratisiz.
  final bool background;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: LogoPainter(background: background));
}

class LogoPainter extends CustomPainter {
  const LogoPainter({this.background = true});
  final bool background;

  static const iris = Color(0xFF6B5CF0);
  static const irisDeep = Color(0xFF3A2BB0);
  static const spark = Color(0xFFFFB547);
  static const page = Color(0xFFFFFFFF);
  static const pageShade = Color(0xFFE6E2FF);
  static const line = Color(0x664A3BD0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    if (background) {
      final rect = RRect.fromLTRBR(0, 0, 100, 100, const Radius.circular(23));
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [iris, irisDeep],
          ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
      );
    }

    // Kitob soyasi
    final shadow = Path()
      ..moveTo(50, 79)
      ..cubicTo(39, 72, 27, 71, 16, 73)
      ..lineTo(16, 70)
      ..lineTo(84, 70)
      ..lineTo(84, 73)
      ..cubicTo(73, 71, 61, 72, 50, 79)
      ..close();
    canvas.drawPath(shadow, Paint()..color = const Color(0x33000000));

    // Chap sahifa
    final left = Path()
      ..moveTo(48.5, 75)
      ..cubicTo(39, 68, 28, 67, 17, 69)
      ..lineTo(17, 37)
      ..cubicTo(28, 35, 39, 37, 48.5, 44)
      ..close();
    canvas.drawPath(left, Paint()..color = page);

    // O'ng sahifa
    final right = Path()
      ..moveTo(51.5, 75)
      ..cubicTo(61, 68, 72, 67, 83, 69)
      ..lineTo(83, 37)
      ..cubicTo(72, 35, 61, 37, 51.5, 44)
      ..close();
    canvas.drawPath(right, Paint()..color = pageShade);

    // Matn qatorlari
    final lp = Paint()
      ..color = line
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(24, 47), const Offset(42, 50.5), lp);
    canvas.drawLine(const Offset(24, 54), const Offset(42, 57.5), lp);
    canvas.drawLine(const Offset(24, 61), const Offset(36, 63), lp);
    canvas.drawLine(const Offset(76, 47), const Offset(58, 50.5), lp);
    canvas.drawLine(const Offset(76, 54), const Offset(58, 57.5), lp);
    canvas.drawLine(const Offset(76, 61), const Offset(64, 63), lp);

    // Uchqun (tushunish lahzasi)
    final star = Path()
      ..moveTo(50, 9)
      ..quadraticBezierTo(51.8, 19.2, 62, 21)
      ..quadraticBezierTo(51.8, 22.8, 50, 33)
      ..quadraticBezierTo(48.2, 22.8, 38, 21)
      ..quadraticBezierTo(48.2, 19.2, 50, 9)
      ..close();
    canvas.drawPath(star, Paint()..color = spark);
    final small = Path()
      ..moveTo(67, 8)
      ..quadraticBezierTo(67.7, 11.3, 71, 12)
      ..quadraticBezierTo(67.7, 12.7, 67, 16)
      ..quadraticBezierTo(66.3, 12.7, 63, 12)
      ..quadraticBezierTo(66.3, 11.3, 67, 8)
      ..close();
    canvas.drawPath(small, Paint()..color = spark.withValues(alpha: 0.85));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LogoPainter old) => old.background != background;
}
