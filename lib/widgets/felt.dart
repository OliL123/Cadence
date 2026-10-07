// The mahjong table's look — wooden rim, striped green felt, ivory tiles on a
// coloured lip — shared so the Focus wall and Career's goals board match.
import 'package:flutter/material.dart';

const feltTop = Color(0xFF1B6B4D);
const feltBottom = Color(0xFF123F2D);
const feltBar = Color(0xFF0F3625);
const tileGreen = Color(0xFF14C47D);

/// Faint diagonal stripes over the felt.
class FeltStripes extends CustomPainter {
  const FeltStripes();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x10FFFFFF)
      ..strokeWidth = 7;
    const gap = 22.0;
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A felt table in a wooden rim, with [child] laid on the felt.
class FeltTable extends StatelessWidget {
  final Widget child;
  final double rim;
  const FeltTable({super.key, required this.child, this.rim = 9});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9A6A3A), Color(0xFF7A4E28), Color(0xFF5A3818)],
              stops: [0.0, 0.5, 1.0]),
        ),
        padding: EdgeInsets.all(rim),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0x33FFE0B0), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [feltTop, feltBottom]),
              ),
              child: Stack(children: [
                const Positioned.fill(child: CustomPaint(painter: FeltStripes())),
                child,
              ]),
            ),
          ),
        ),
      );
}

/// An ivory tile face on a coloured lip — the mahjong tile, as a card.
class IvoryTile extends StatelessWidget {
  final Widget child;
  final Color lip;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const IvoryTile({
    super.key,
    required this.child,
    this.lip = tileGreen,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(13, 11, 13, 12),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: lip,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 11, offset: Offset(0, 6)),
            ],
          ),
          padding: const EdgeInsets.only(bottom: 5),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(9),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFDFBF3), Color(0xFFECE4CE)]),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      );
}
