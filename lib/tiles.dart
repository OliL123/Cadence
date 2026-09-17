import 'package:flutter/material.dart';
import 'models.dart';

const _man = Color(0xFFBE3A2B);
const _pin = Color(0xFF2C4C7C);
const _sok = Color(0xFF1F6E4E);

Color tileColor(Tile t) {
  switch (t.suit) {
    case 'm':
      return _man;
    case 'p':
      return _pin;
    case 's':
      return _sok;
    default:
      return t.val == 1 ? _man : (t.val == 2 ? _sok : _pin);
  }
}

/// The painted face of a mahjong tile (no border/shadow — that's the tile body).
class TileFace extends StatelessWidget {
  final Tile tile;
  final double width;
  final double height;
  const TileFace(this.tile, {this.width = 34, this.height = 44, super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: _TileFacePainter(tile));
}

class _TileFacePainter extends CustomPainter {
  final Tile t;
  _TileFacePainter(this.t);

  static const _val = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

  // normalized pip layouts (0..1 within the face)
  static const Map<int, List<Offset>> _pos = {
    1: [Offset(.5, .5)],
    2: [Offset(.5, .28), Offset(.5, .72)],
    3: [Offset(.27, .24), Offset(.5, .5), Offset(.73, .76)],
    4: [Offset(.3, .26), Offset(.7, .26), Offset(.3, .74), Offset(.7, .74)],
    5: [Offset(.3, .26), Offset(.7, .26), Offset(.5, .5), Offset(.3, .74), Offset(.7, .74)],
    6: [Offset(.3, .24), Offset(.7, .24), Offset(.3, .5), Offset(.7, .5), Offset(.3, .76), Offset(.7, .76)],
    7: [Offset(.5, .18), Offset(.3, .42), Offset(.7, .42), Offset(.3, .62), Offset(.7, .62), Offset(.3, .82), Offset(.7, .82)],
    8: [Offset(.3, .18), Offset(.7, .18), Offset(.3, .40), Offset(.7, .40), Offset(.3, .62), Offset(.7, .62), Offset(.3, .84), Offset(.7, .84)],
    9: [Offset(.26, .24), Offset(.5, .24), Offset(.74, .24), Offset(.26, .5), Offset(.5, .5), Offset(.74, .5), Offset(.26, .76), Offset(.5, .76), Offset(.74, .76)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final col = tileColor(t);
    switch (t.suit) {
      case 'm':
        _text(canvas, size, _val[t.val], col, size.height * 0.42,
            Offset(size.width / 2, size.height * 0.33), FontWeight.w900);
        _text(canvas, size, '萬', col, size.height * 0.26,
            Offset(size.width / 2, size.height * 0.72), FontWeight.w700);
        break;
      case 'z':
        final ch = t.val == 1 ? '中' : (t.val == 2 ? '發' : '白');
        _text(canvas, size, ch, col, size.height * 0.5,
            Offset(size.width / 2, size.height * 0.5), FontWeight.w900);
        break;
      case 'p':
        _dots(canvas, size, col);
        break;
      case 's':
        if (t.val == 1) {
          _bird(canvas, size, col);
        } else {
          _bamboo(canvas, size, col);
        }
        break;
    }
  }

  void _dots(Canvas canvas, Size size, Color col) {
    final r = size.width * 0.115;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..color = col;
    final core = Paint()..color = col;
    for (final p in _pos[t.val] ?? _pos[9]!) {
      final c = Offset(p.dx * size.width, p.dy * size.height);
      canvas.drawCircle(c, r, ring);
      canvas.drawCircle(c, r * 0.34, core);
    }
  }

  void _bamboo(Canvas canvas, Size size, Color col) {
    final stroke = Paint()
      ..color = col
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;
    final thin = Paint()
      ..color = col
      ..strokeWidth = size.width * 0.04;
    final h = size.height * 0.11;
    final w = size.width * 0.075;
    for (final p in _pos[t.val] ?? _pos[9]!) {
      final c = Offset(p.dx * size.width, p.dy * size.height);
      canvas.drawLine(Offset(c.dx, c.dy - h), Offset(c.dx, c.dy + h), stroke);
      canvas.drawLine(Offset(c.dx - w, c.dy), Offset(c.dx + w, c.dy), thin);
    }
  }

  void _bird(Canvas canvas, Size size, Color col) {
    final w = size.width, h = size.height;
    final body = Paint()
      ..color = col.withValues(alpha: .18)
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final bodyPath = Path()
      ..moveTo(w * 0.55, h * 0.30)
      ..quadraticBezierTo(w * 0.82, h * 0.34, w * 0.80, h * 0.55)
      ..quadraticBezierTo(w * 0.78, h * 0.80, w * 0.48, h * 0.82)
      ..quadraticBezierTo(w * 0.28, h * 0.83, w * 0.24, h * 0.62);
    canvas.drawPath(bodyPath, body);
    canvas.drawPath(bodyPath, line);
    canvas.drawCircle(Offset(w * 0.42, h * 0.28), w * 0.09, body);
    canvas.drawCircle(Offset(w * 0.42, h * 0.28), w * 0.09, line);
    canvas.drawLine(Offset(w * 0.34, h * 0.25), Offset(w * 0.18, h * 0.20), line); // beak
    canvas.drawLine(Offset(w * 0.5, h * 0.82), Offset(w * 0.35, h * 0.98), line); // tail
    canvas.drawLine(Offset(w * 0.62, h * 0.55), Offset(w * 0.66, h * 0.95), line); // leg
  }

  void _text(Canvas canvas, Size size, String s, Color col, double fontSize,
      Offset center, FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            color: col,
            fontSize: fontSize,
            fontWeight: weight,
            fontFamily: 'serif',
            height: 1),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TileFacePainter old) =>
      old.t.suit != t.suit || old.t.val != t.val;
}
