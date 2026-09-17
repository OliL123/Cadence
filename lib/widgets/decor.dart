import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../palette.dart';

/// A row in a popup menu: an icon, a label, and a danger variant.
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const MenuRow(this.icon, this.label, {this.danger = false, super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 17, color: danger ? C.red : C.ink2),
        const SizedBox(width: 11),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: danger ? C.red : C.ink)),
      ]);
}

/// Lets the board pan by mouse drag (not just touch/trackpad), so wide-screen
/// mouse users can scroll the board horizontally.
class DragScrollBehavior extends MaterialScrollBehavior {
  const DragScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// The green 窗花 (window-grille) lattice strip across the top of the masthead.
class LatticeStrip extends StatelessWidget {
  const LatticeStrip({super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: SizedBox(
          height: 15,
          width: double.infinity,
          child: CustomPaint(painter: _LatticePainter()),
        ),
      );
}

class _LatticePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = C.paper2);
    final p = Paint()
      ..color = C.green.withValues(alpha: .85)
      ..strokeWidth = 1.6;
    for (double x = 0; x <= size.width; x += 15) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += 15) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Chronicle's logogram: a red wax seal with a cream "C" monogram, standing in
/// for Cadence's 節奏 in the masthead.
class SealMark extends StatelessWidget {
  final double size;
  const SealMark({super.key, this.size = 58});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _SealPainter()));
}

class _SealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * .16)),
      Paint()..color = C.red,
    );
    // cream inner keyline
    final inset = w * .12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, w - 2 * inset, s.height - 2 * inset),
          Radius.circular(w * .08)),
      Paint()
        ..color = C.creamTxt.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .03,
    );
    // a cream "C" monogram
    final mark = Paint()
      ..color = C.creamTxt
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .08
      ..strokeCap = StrokeCap.round;
    final rad = w * .21;
    const pi = 3.14159;
    // a "C": arc with a gap on the right side
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2, s.height / 2), radius: rad),
      0.30 * pi, // start lower-right
      1.40 * pi, // sweep clockwise, leaving the right open
      false,
      mark,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
