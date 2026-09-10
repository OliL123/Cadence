import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'palette.dart';
import 'models.dart';
import 'store.dart';

/// Chronicle's focus wall: the same mechanic as the mahjong wall (starred tasks
/// are "drawn", reorderable, tick to finish) rendered as a tarot spread on a
/// night cloth. Each task is dealt a Major Arcana card derived from its id, so
/// no store changes are needed — it reads the same [store.wallTasks].
class SpreadWall extends StatelessWidget {
  final bool showHeader;
  const SpreadWall({super.key, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final ws = store.wallTasks();
        return Container(
          // gilt frame
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFC9A24A), Color(0xFF9A7327), Color(0xFF6E5018)]),
          ),
          padding: const EdgeInsets.all(9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0x55FFE9B0), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [C.night, C.night2]),
                  boxShadow: [BoxShadow(color: Color(0x88000000), blurRadius: 8, spreadRadius: -2)],
                ),
                child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _StarfieldPainter())),
                  Column(children: [
                    if (showHeader) _header(),
                    Expanded(
                      child: ws.isEmpty
                          ? _empty()
                          : ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
                              buildDefaultDragHandles: false,
                              proxyDecorator: _dragProxy,
                              itemCount: ws.length,
                              onReorder: store.reorderWall,
                              itemBuilder: (context, i) => _cardRow(ws[i], i),
                            ),
                    ),
                    _footer(),
                  ]),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1.0 + 0.04 * t,
          child: Transform.rotate(angle: -0.015 * t,
              child: Material(color: Colors.transparent, elevation: 0, child: child)),
        );
      },
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 13, 12, 6),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('The Spread',
                style: _play(26, FontWeight.w700, C.creamTxt).copyWith(letterSpacing: 1.2, shadows: const [
                  Shadow(color: Color(0x77000000), offset: Offset(1, 2), blurRadius: 4)
                ])),
            const SizedBox(height: 1),
            Text('✦   your focus, dealt as cards   ✦',
                style: _gar(11, const Color(0xFFD8CFAE)).copyWith(fontStyle: FontStyle.italic)),
          ]),
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('no cards drawn\nstar a task\nto deal one',
              textAlign: TextAlign.center,
              style: _gar(13, C.creamTxt.withValues(alpha: .7)).copyWith(height: 1.6)),
        ),
      );

  Widget _footer() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 13),
        child: Column(children: [
          Text('lay the Major Arcana in a line',
              style: _gar(10.5, C.mustard).copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 3),
          Text('drawn ${store.wall.length}  ·  deck ${store.deckLeft}/${CadenceStore.deckTotal}  ·  streak ${store.streak}',
              textAlign: TextAlign.center,
              style: _gar(9.5, C.creamTxt.withValues(alpha: .6)).copyWith(letterSpacing: .5)),
        ]),
      );

  Widget _cardRow(Task t, int i) {
    final g = store.groupOf(t.group);
    final arc = _arcana[t.id % _arcana.length];
    return Padding(
      key: ValueKey(t.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFDFBF3), Color(0xFFECE4CE)]),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFD9CFB1)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 9, offset: Offset(0, 5))],
        ),
        // group-coloured lip along the bottom, like the tile back
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border(bottom: BorderSide(color: g.c, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(9, 8, 4, 8),
        child: Row(children: [
          _TarotFace(arc, width: 42, height: 60),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF2A2418))),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: g.c, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Flexible(child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: _gar(10.5, const Color(0xFF7C7358)))),
                    const SizedBox(width: 8),
                    Text(arc.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: _play(9.5, FontWeight.w600, const Color(0xFF8A6A1E)).copyWith(fontStyle: FontStyle.italic)),
                  ]),
                ]),
          ),
          GestureDetector(
            onTap: () => store.toggleDone(t),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF8A6A1E)),
            ),
          ),
          ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.only(left: 2, right: 4),
              child: Icon(Icons.drag_handle, size: 17, color: Color(0xFFBBAF88)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---- fonts (kept local so this file needs no google_fonts import churn) ----
// The app's global text theme is already EB Garamond in Chronicle builds; these
// helpers just set weight/size/colour explicitly.
TextStyle _play(double s, FontWeight w, Color c) =>
    TextStyle(fontFamily: 'Playfair Display', fontSize: s, fontWeight: w, color: c);
TextStyle _gar(double s, Color c) =>
    TextStyle(fontFamily: 'EB Garamond', fontSize: s, color: c);

// ---- major arcana ----------------------------------------------------------
class _Arc {
  final String num;
  final String name;
  final String kind; // emblem: sun/moon/star/wheel/tower/rose
  const _Arc(this.num, this.name, this.kind);
}

const _arcana = <_Arc>[
  _Arc('0', 'The Fool', 'rose'),
  _Arc('I', 'The Magician', 'rose'),
  _Arc('II', 'The High Priestess', 'moon'),
  _Arc('III', 'The Empress', 'rose'),
  _Arc('IV', 'The Emperor', 'tower'),
  _Arc('V', 'The Hierophant', 'rose'),
  _Arc('VI', 'The Lovers', 'sun'),
  _Arc('VII', 'The Chariot', 'wheel'),
  _Arc('VIII', 'Strength', 'sun'),
  _Arc('IX', 'The Hermit', 'star'),
  _Arc('X', 'Wheel of Fortune', 'wheel'),
  _Arc('XI', 'Justice', 'rose'),
  _Arc('XII', 'The Hanged Man', 'rose'),
  _Arc('XIII', 'Death', 'rose'),
  _Arc('XIV', 'Temperance', 'star'),
  _Arc('XV', 'The Devil', 'tower'),
  _Arc('XVI', 'The Tower', 'tower'),
  _Arc('XVII', 'The Star', 'star'),
  _Arc('XVIII', 'The Moon', 'moon'),
  _Arc('XIX', 'The Sun', 'sun'),
  _Arc('XX', 'Judgement', 'sun'),
  _Arc('XXI', 'The World', 'wheel'),
];

/// A small Rider-Waite-style card face: cream, black keyline, Roman numeral,
/// a gilded emblem over a classical-blue sky, and a titled banner.
class _TarotFace extends StatelessWidget {
  final _Arc arc;
  final double width, height;
  const _TarotFace(this.arc, {required this.width, required this.height});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFFF3ECD8),
          border: Border.all(color: const Color(0xFF201C13), width: 1.4),
          borderRadius: BorderRadius.circular(3),
          boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF201C13), width: .8)),
          child: Column(children: [
            Text(arc.num,
                style: _play(6.5, FontWeight.w600, const Color(0xFF201C13)).copyWith(height: 1.4)),
            Expanded(child: CustomPaint(painter: _EmblemPainter(arc.kind), size: Size.infinite)),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF201C13), width: .8))),
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(arc.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.center,
                  style: _play(5, FontWeight.w700, const Color(0xFF201C13)).copyWith(letterSpacing: .2)),
            ),
          ]),
        ),
      );
}

class _EmblemPainter extends CustomPainter {
  final String kind;
  _EmblemPainter(this.kind);
  static const _sky = Color(0xFF2F56A0);
  static const _skyD = Color(0xFF233F78);
  static const _gold = Color(0xFFDCBB63);
  static const _goldD = Color(0xFF8A6A1E);

  @override
  void paint(Canvas canvas, Size s) {
    // sky ground
    canvas.drawRect(Offset.zero & s,
        Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_sky, _skyD]).createShader(Offset.zero & s));
    final cx = s.width / 2, cy = s.height / 2;
    final r = s.shortestSide * 0.28;
    final gold = Paint()..color = _gold;
    final goldStroke = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.shortestSide * 0.06
      ..strokeCap = StrokeCap.round;
    final outline = Paint()
      ..color = _goldD
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6;

    switch (kind) {
      case 'sun':
        for (var k = 0; k < 8; k++) {
          final a = k * math.pi / 4;
          canvas.drawLine(
              Offset(cx + (r + 2) * math.cos(a), cy + (r + 2) * math.sin(a)),
              Offset(cx + (r + 6) * math.cos(a), cy + (r + 6) * math.sin(a)), goldStroke);
        }
        canvas.drawCircle(Offset(cx, cy), r, gold);
        canvas.drawCircle(Offset(cx, cy), r, outline);
        break;
      case 'moon':
        final p = Path()
          ..addOval(Rect.fromCircle(center: Offset(cx + 2, cy), radius: r + 1))
          ..addOval(Rect.fromCircle(center: Offset(cx + r * 0.7, cy - r * 0.3), radius: r + 1))
          ..fillType = PathFillType.evenOdd;
        canvas.drawPath(p, gold);
        break;
      case 'star':
        _star(canvas, cx, cy, r + 4, r * 0.5, 8, gold);
        canvas.drawCircle(Offset(cx - r, cy + r), 1, gold);
        canvas.drawCircle(Offset(cx + r, cy - r * 0.6), .8, gold);
        break;
      case 'wheel':
        canvas.drawCircle(Offset(cx, cy), r, goldStroke..style = PaintingStyle.stroke);
        for (var k = 0; k < 8; k++) {
          final a = k * math.pi / 4;
          canvas.drawLine(Offset(cx, cy), Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
              Paint()..color = _gold..strokeWidth = s.shortestSide * 0.03);
        }
        break;
      case 'tower':
        final w = r * 1.1;
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy + 2), width: w, height: r * 2), gold);
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy - r), width: w + 4, height: 4), gold);
        break;
      default: // rose / rosette
        canvas.drawCircle(Offset(cx, cy), r, goldStroke..style = PaintingStyle.stroke);
        canvas.drawCircle(Offset(cx, cy), r * 0.6, goldStroke..style = PaintingStyle.stroke);
        canvas.drawCircle(Offset(cx, cy), r * 0.22, gold..style = PaintingStyle.fill);
    }
  }

  void _star(Canvas c, double cx, double cy, double rOut, double rIn, int pts, Paint p) {
    final path = Path();
    for (var k = 0; k < pts * 2; k++) {
      final rr = k.isEven ? rOut : rIn;
      final a = k * math.pi / pts - math.pi / 2;
      final x = cx + rr * math.cos(a), y = cy + rr * math.sin(a);
      k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) => old.kind != kind;
}

class _StarfieldPainter extends CustomPainter {
  static const _pts = [
    [.14, .18], [.32, .40], [.55, .12], [.72, .30], [.86, .20],
    [.22, .66], [.44, .80], [.62, .58], [.80, .74], [.90, .50],
    [.10, .88], [.50, .30], [.68, .90], [.36, .14], [.94, .84],
  ];
  @override
  void paint(Canvas canvas, Size s) {
    final gold = Paint()..color = const Color(0x66DCBB63);
    final white = Paint()..color = const Color(0x55FFFFFF);
    for (var i = 0; i < _pts.length; i++) {
      final p = _pts[i];
      canvas.drawCircle(Offset(p[0] * s.width, p[1] * s.height), i.isEven ? 1.0 : .7,
          i % 3 == 0 ? white : gold);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
