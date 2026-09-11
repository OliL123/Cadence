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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        itemCount: ws.length,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, i) => _row(ws[i]),
      );

  // One focus task = a card strip: the tarot card + its title, tick to finish.
  Widget _row(Task t) {
    final g = store.groupOf(t.group);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFFBF6EA), Color(0xFFEFE6CF)]),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFD9CFB1)),
        boxShadow: const [BoxShadow(color: Color(0x66051022), blurRadius: 9, offset: Offset(0, 5))],
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
      child: Row(children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF2A2418), width: 1.4),
            borderRadius: BorderRadius.circular(3),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(Chron.arcana(t.id), width: 46, height: 80, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ebGaramond(
                    fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF2A2418), height: 1.2)),
            const SizedBox(height: 5),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: g.c, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Flexible(
                child: Text(g.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.ebGaramond(fontSize: 11.5, color: const Color(0xFF7C7358))),
              ),
              if (store.dueLabel(t) != null) ...[
                const SizedBox(width: 8),
                Text('◷ ${store.dueLabel(t)}',
                    style: GoogleFonts.ebGaramond(
                        fontSize: 11, color: store.soon(t) ? const Color(0xFFB1382C) : const Color(0xFF9A8F74))),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => store.toggleDone(t),
          child: Container(
            width: 34, height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF5F6A3A), width: 1.6),
            ),
            child: const Icon(Icons.check, size: 18, color: Color(0xFF5F6A3A)),
          ),
        ),
      ]),
    );
  }
}
