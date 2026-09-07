import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'palette.dart';
import 'models.dart';
import 'store.dart';
import 'tiles.dart';

const _feltTop = Color(0xFF1B6B4D);
const _feltBottom = Color(0xFF123F2D);
const _feltBar = Color(0xFF0F3625);
const _tileGreen = Color(0xFF14C47D);
const _winCol = Color(0xFF38C07F);
const _daaiCol = Color(0xFFA31545);

/// Full-page wrapper for the mahjong wall (used on narrow layouts).
class MahjongPage extends StatelessWidget {
  const MahjongPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _feltBottom,
      appBar: AppBar(
        backgroundColor: _feltBar,
        foregroundColor: C.creamTxt,
        elevation: 0,
        title: Row(children: [
          Text('麻雀',
              style: GoogleFonts.notoSerifHk(
                  fontWeight: FontWeight.w900, fontSize: 22, color: C.creamTxt)),
          const SizedBox(width: 10),
          Text('FOCUS',
              style: GoogleFonts.oswald(
                  fontSize: 13, color: C.mustard, fontWeight: FontWeight.w600)),
        ]),
      ),
      body: const FocusWall(showHeader: false),
    );
  }
}

/// The felt table with tiles — embeddable (right column) or full-page.
class FocusWall extends StatefulWidget {
  final bool showHeader;
  const FocusWall({super.key, this.showHeader = true});
  @override
  State<FocusWall> createState() => _FocusWallState();
}

class _FocusWallState extends State<FocusWall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  String? _badgeCn;
  String? _badgeEn;
  Color _badgeCol = _winCol;
  String _lastSig = '';
  bool _soundOn = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStore());
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    _hide?.cancel();
    _pop.dispose();
    super.dispose();
  }

  static String? _meld3(Tile a, Tile b, Tile c) {
    if (a.suit == b.suit && b.suit == c.suit) {
      if (a.val == b.val && b.val == c.val) return 'peng';
      if (a.suit == 'z') {
        final s = [a.val, b.val, c.val]..sort();
        return (s[0] == 1 && s[1] == 2 && s[2] == 3) ? 'daai' : null;
      }
      final v = [a.val, b.val, c.val]..sort();
      if (v[0] + 1 == v[1] && v[1] + 1 == v[2]) return 'shang';
    }
    return null;
  }

  (String?, Set<int>) _detect(List<Task> ws) {
    final tiles = ws.map((t) => t.tile!).toList();
    if (tiles.length >= 4 &&
        tiles.every((x) => x.suit == tiles[0].suit && x.suit != 'z')) {
      final vals = tiles.map((x) => x.val).toList()..sort();
      var run = true;
      for (var i = 1; i < vals.length; i++) {
        if (vals[i] != vals[i - 1] + 1) run = false;
      }
      if (run) return ('win', ws.map((t) => t.id).toSet());
    }
    for (var i = 0; i + 2 < tiles.length; i++) {
      final m = _meld3(tiles[i], tiles[i + 1], tiles[i + 2]);
      if (m != null) return (m, {ws[i].id, ws[i + 1].id, ws[i + 2].id});
    }
    return (null, <int>{});
  }

  Color _colorFor(String type) => switch (type) {
        'shang' => C.mustard,
        'peng' => C.red,
        'daai' => _daaiCol,
        _ => _winCol,
      };

  void _onStore() {
    final ws = store.wallTasks();
    final (type, _) = _detect(ws);
    final sig = '${ws.map((t) => t.id).join('-')}:${type ?? ''}';
    if (type != null && sig != _lastSig) _fire(type);
    _lastSig = sig;
    if (mounted) setState(() {});
  }

  void _fire(String type) {
    const label = {
      'shang': ('上', 'SHANG · RUN'),
      'peng': ('碰', 'PENG · TRIPLET'),
      'win': ('食糊', 'FULL RUN!'),
      'daai': ('大牌', 'THREE DRAGONS!'),
    };
    final m = label[type]!;
    setState(() {
      _badgeCn = m.$1;
      _badgeEn = m.$2;
      _badgeCol = _colorFor(type);
    });
    _pop.forward(from: 0);
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _badgeCn = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final ws = store.wallTasks();
        final (type, meldIds) = _detect(ws);
        final meldCol = type == null ? null : _colorFor(type);
        return Container(
          // warm wooden table rim — fills its slot squarely so the surrounding
          // enamel border/dividers meet it flush (no cream gap at the corners).
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF9A6A3A), Color(0xFF7A4E28), Color(0xFF5A3818)],
                stops: [0.0, 0.5, 1.0]),
          ),
          padding: const EdgeInsets.all(9),
          child: Container(
            // subtle lighter top-edge bevel on the rim
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0x33FFE0B0), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(children: [
          // dark groove where felt sits into the wood
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_feltTop, _feltBottom]),
              boxShadow: [
                BoxShadow(color: Color(0x66000000), blurRadius: 6, spreadRadius: -2),
              ],
            ),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _FeltStripes())),
              Column(children: [
                if (widget.showHeader) _header(),
                Expanded(
                  child: ws.isEmpty
                      ? _empty()
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                          buildDefaultDragHandles: false,
                          proxyDecorator: _dragProxy,
                          itemCount: ws.length,
                          onReorder: store.reorderWall,
                          itemBuilder: (context, i) => _tileRow(ws[i], i,
                              meldIds.contains(ws[i].id) ? meldCol : null),
                        ),
                ),
                _footer(),
              ]),
            ]),
          ),
          if (_badgeCn != null) _badge(),
            ]),
            ),
          ),
        );
      },
    );
  }

  // Keeps the tile's own look while dragging (no white Material box), with a
  // slight lift + tilt so it feels picked up off the felt.
  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1.0 + 0.04 * t,
          child: Transform.rotate(
            angle: -0.015 * t,
            child: Material(
              color: Colors.transparent,
              elevation: 0,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 6),
        child: Row(children: [
          const SizedBox(width: 34),
          Expanded(
            child: Center(
              child: Text('麻雀',
                  style: GoogleFonts.notoSerifHk(
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                      color: C.creamTxt,
                      shadows: const [
                        Shadow(color: Color(0x66000000), offset: Offset(1, 2), blurRadius: 4)
                      ])),
            ),
          ),
          _soundBtn(),
        ]),
      );

  Widget _soundBtn() => GestureDetector(
        onTap: () => setState(() => _soundOn = !_soundOn),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: C.creamTxt.withValues(alpha: .25)),
          ),
          child: Icon(_soundOn ? Icons.volume_up : Icons.volume_off,
              size: 16, color: C.creamTxt),
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('冇牌\nstar a task to\ndraw a tile',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceMono(
                  color: C.creamTxt.withValues(alpha: .7), fontSize: 12, height: 1.6)),
        ),
      );

  Widget _footer() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        child: Column(children: [
          Text('drag to line up a 上 / 碰',
              style: GoogleFonts.spaceMono(color: C.mustard, fontSize: 10.5)),
          const SizedBox(height: 4),
          Text(
              '牌 ${store.wall.length} · deck ${store.deckLeft}/${CadenceStore.deckTotal} · 連勝 ${store.streak}',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceMono(
                  color: C.creamTxt.withValues(alpha: .6), fontSize: 9.5)),
        ]),
      );

  Widget _tileRow(Task t, int i, Color? meldCol) {
    final g = store.groupOf(t.group);
    final melded = meldCol != null;
    return Padding(
      key: ValueKey(t.id),
      padding: const EdgeInsets.only(bottom: 13),
      // green "tile back" lip behind an ivory face
      child: Container(
        decoration: BoxDecoration(
          color: melded ? meldCol : _tileGreen,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            if (melded) BoxShadow(color: meldCol.withValues(alpha: .6), blurRadius: 18),
            const BoxShadow(color: Color(0x66000000), blurRadius: 11, offset: Offset(0, 6)),
          ],
        ),
        padding: const EdgeInsets.only(bottom: 5),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFDFBF3), Color(0xFFECE4CE)]),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFD9CFB1)),
          ),
          padding: const EdgeInsets.fromLTRB(11, 9, 4, 9),
          child: Row(children: [
          SizedBox(
              width: 42,
              height: 52,
              child: Center(child: TileFace(t.tile!, width: 40, height: 50))),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF2A2418))),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration:
                            BoxDecoration(color: g.c, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceMono(
                              fontSize: 10.5, color: const Color(0xFF7C7358))),
                    ),
                  ]),
                ]),
          ),
          GestureDetector(
            onTap: () => store.toggleDone(t),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF1F6E4E)),
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
      ),
    );
  }

  Widget _badge() => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _badgeCol,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Color(0x88000000), blurRadius: 24, offset: Offset(0, 10))
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_badgeCn!,
                      style: GoogleFonts.notoSerifHk(
                          fontWeight: FontWeight.w900, fontSize: 26, color: C.creamTxt)),
                  Text(_badgeEn!,
                      style: GoogleFonts.oswald(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: C.creamTxt,
                          letterSpacing: 1.5)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Subtle diagonal weave on the felt.
class _FeltStripes extends CustomPainter {
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
