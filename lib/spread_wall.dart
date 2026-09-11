import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';
import 'store.dart';
import 'chronicle.dart';

/// Chronicle's focus wall — "The Spread". Each starred task is dealt a real
/// Rider–Waite Major Arcana card, laid out over a golden cloud sky. Same
/// mechanic as the mahjong wall (star to draw, tick to finish), skinned.
class SpreadWall extends StatelessWidget {
  final bool showHeader;
  const SpreadWall({super.key, this.showHeader = true});

  TextStyle _cin(double s, FontWeight w, Color c) =>
      GoogleFonts.cinzel(fontSize: s, fontWeight: w, color: c);
  TextStyle _gar(double s, Color c) => GoogleFonts.ebGaramond(fontSize: s, color: c);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final ws = store.wallTasks();
        return Container(
          decoration: BoxDecoration(
            image: const DecorationImage(image: AssetImage(Chron.clouds), fit: BoxFit.cover),
            border: Border.all(color: const Color(0xFF7A5A1E), width: 1.5),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55140C04), Color(0xCC120A03)],
              ),
            ),
            child: Column(children: [
              if (showHeader) _header(),
              Expanded(child: ws.isEmpty ? _empty() : _deck(ws)),
              _footer(),
            ]),
          ),
        );
      },
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('THE SPREAD',
              style: _cin(19, FontWeight.w700, const Color(0xFFF3ECD6))
                  .copyWith(letterSpacing: 2, shadows: const [
                Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 4)
              ])),
          const SizedBox(height: 2),
          Text('your starred tasks, drawn as cards',
              style: _gar(12, const Color(0xFFECDCB6)).copyWith(fontStyle: FontStyle.italic)),
        ]),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('no cards drawn\nstar a task\nto deal one',
              textAlign: TextAlign.center,
              style: _gar(13.5, const Color(0xCCF3ECD6)).copyWith(height: 1.6)),
        ),
      );

  Widget _footer() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
        child: Text('◆  the day’s arcana  ·  ${store.wall.length} drawn  ·  streak ${store.streak}  ◆',
            textAlign: TextAlign.center,
            style: _gar(10.5, const Color(0xB3E7D6AC)).copyWith(fontStyle: FontStyle.italic)),
      );

  Widget _deck(List<Task> ws) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: ws.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _card(ws[i]),
      );

  Widget _card(Task t) {
    final g = store.groupOf(t.group);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFF4EEDE), width: 3),
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [BoxShadow(color: Color(0xAA061226), blurRadius: 14, offset: Offset(0, 8))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(Chron.arcana(t.id), width: 104, height: 179, fit: BoxFit.cover),
        ),
        const SizedBox(height: 7),
        SizedBox(
          width: 116,
          child: Text(t.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.ebGaramond(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFFF3ECD6), height: 1.2)),
        ),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () => store.toggleDone(t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0x88F0E4C4)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check, size: 13, color: Color(0xFFECDCB6)),
                const SizedBox(width: 4),
                Text('done', style: GoogleFonts.ebGaramond(fontSize: 11, color: const Color(0xFFECDCB6))),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          Container(width: 7, height: 7, decoration: BoxDecoration(color: g.c, shape: BoxShape.circle)),
        ]),
      ]),
    );
  }
}
