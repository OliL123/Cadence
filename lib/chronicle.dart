import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'palette.dart';

/// Shared assets, time-of-day theming, and small widgets for the Greek
/// "Chronicle" skin. Everything here is only used behind `if (C.chronicle)`.
class Chron {
  static const _a = 'assets/chronicle/';

  /// Masthead paintings by time-of-day slot (0=dawn … 4=night).
  static const mastAssets = [
    '${_a}mast_dawn.jpg',
    '${_a}mast_day.jpg',
    '${_a}mast_twilight.jpg',
    '${_a}mast_sunset.jpg',
    '${_a}mast_night.jpg',
  ];
  static const capital = '${_a}col_capital.png';
  static const shaft = '${_a}col_shaft.png';
  static const clouds = '${_a}spread_clouds.jpg';
  static String arcana(int id) =>
      '${_a}arcana/${(id % 22).toString().padLeft(2, '0')}.jpg';

  static const _arcanaNames = [
    'The Fool', 'The Magician', 'The High Priestess', 'The Empress', 'The Emperor',
    'The Hierophant', 'The Lovers', 'The Chariot', 'Strength', 'The Hermit',
    'Wheel of Fortune', 'Justice', 'The Hanged Man', 'Death', 'Temperance',
    'The Devil', 'The Tower', 'The Star', 'The Moon', 'The Sun', 'Judgement', 'The World',
  ];
  static const _numerals = [
    '0', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X',
    'XI', 'XII', 'XIII', 'XIV', 'XV', 'XVI', 'XVII', 'XVIII', 'XIX', 'XX', 'XXI',
  ];
  static String arcanaName(int id) => _arcanaNames[id % 22];
  static String arcanaNumeral(int id) => _numerals[id % 22];

  /// The time-of-day slot (0..4) for a given hour — dawn/day/twilight/sunset/night.
  static int slotForHour(int h) {
    if (h >= 5 && h < 8) return 0; // dawn
    if (h >= 8 && h < 16) return 1; // day
    if (h >= 16 && h < 18) return 2; // twilight
    if (h >= 18 && h < 20) return 3; // sunset
    return 4; // night
  }

  static int slotNow() => slotForHour(DateTime.now().hour);

  // Ground gradient colours per slot (top, bottom).
  static const groundTop = [
    Color(0xFFF5E7C6), Color(0xFFE2E8E5), Color(0xFFEFE0CD), Color(0xFFF1DCBB), Color(0xFFDDE3EC),
  ];
  static const groundBot = [
    Color(0xFFECDCBA), Color(0xFFECE5D4), Color(0xFFE7DCC4), Color(0xFFE6D5B3), Color(0xFFE1DDD3),
  ];
}

/// Continuously-fading marble ground: cycles the five time-of-day tints as one
/// smooth loop (no discrete stages), with a faint stone grain over it.
class ChronGround extends StatefulWidget {
  final Widget child;
  const ChronGround({super.key, required this.child});
  @override
  State<ChronGround> createState() => _ChronGroundState();
}

class _ChronGroundState extends State<ChronGround> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 90))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color _lerpList(List<Color> cs, double t) {
    final n = cs.length;
    final p = (t * n) % n;
    final i = p.floor();
    return Color.lerp(cs[i % n], cs[(i + 1) % n], p - i)!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final top = _lerpList(Chron.groundTop, t);
        final bot = _lerpList(Chron.groundBot, t);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.15),
              radius: 1.4,
              colors: [top, bot],
              stops: const [0, .62],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Two fluted contour columns (capital + tiling shaft), half off each page edge.
class ChronColumns extends StatelessWidget {
  const ChronColumns({super.key});

  Widget _one({required bool left}) {
    final col = Opacity(
      opacity: .85,
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(Chron.capital, width: 96, fit: BoxFit.fitWidth),
            Expanded(
              child: SizedBox(
                width: 50,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(Chron.shaft),
                      repeat: ImageRepeat.repeatY,
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Positioned(
      top: 0,
      bottom: 0,
      left: left ? -48 : null,
      right: left ? null : -48,
      child: left
          ? col
          : Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1, 1, 1),
              child: col,
            ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: Stack(children: [_one(left: true), _one(left: false)]));
}

/// The focus mark: a small olive sprig. [lit] = drawn into The Spread.
class OliveSprig extends StatelessWidget {
  final bool lit;
  final double size;
  const OliveSprig({super.key, required this.lit, this.size = 21});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 1.08,
        child: CustomPaint(painter: _SprigPainter(lit ? C.olive : C.line)),
      );
}

class _SprigPainter extends CustomPainter {
  final Color c;
  _SprigPainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 22.0; // design in a 22-wide box
    final stem = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * u
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(11 * u, 23 * u)
      ..cubicTo(10 * u, 17 * u, 9 * u, 12.5 * u, 13 * u, 4.5 * u);
    canvas.drawPath(path, stem);
    final leaf = Paint()..color = c;
    void ell(double cx, double cy, double rx, double ry, double deg) {
      canvas.save();
      canvas.translate(cx * u, cy * u);
      canvas.rotate(deg * math.pi / 180);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2 * u, height: ry * 2 * u), leaf);
      canvas.restore();
    }
    ell(6.6, 16, 3.1, 1.5, 32);
    ell(15, 12.5, 3.1, 1.5, -32);
    ell(7.6, 10.5, 2.7, 1.3, 38);
    ell(14.2, 7.6, 2.7, 1.3, -38);
    canvas.drawCircle(Offset(13 * u, 4.4 * u), 1.9 * u, leaf);
  }

  @override
  bool shouldRepaint(covariant _SprigPainter old) => old.c != c;
}

/// A small red wax seal stamped on finished tasks.
class WaxSeal extends StatelessWidget {
  final double size;
  const WaxSeal({super.key, this.size = 20});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(-.3, -.4),
            radius: .95,
            colors: [Color(0xFFC1442F), Color(0xFF8F2416)],
            stops: [0, .8],
          ),
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Icon(Icons.star, size: size * .5, color: const Color(0x66EFC9A6)),
      );
}
