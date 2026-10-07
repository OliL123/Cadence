// A hover card: what a chip is, laid out as a small paper card — a coloured
// kicker naming the kind of thing, the full title, then labelled rows —
// instead of a plain run of lines in a dark tooltip box.
import 'package:flutter/material.dart';

import '../palette.dart';
import 'type.dart';

class TipCard {
  final String kicker; // e.g. "UNI" or "CAREER · SIGN-UP OPENS"
  final Color accent;
  final String title;
  final List<(String, String)> rows; // (label, value); empty values are skipped

  const TipCard({
    required this.kicker,
    required this.accent,
    required this.title,
    this.rows = const [],
  });

  /// Wraps [child] so hovering (desktop/web) or long-pressing (phone) shows
  /// this card.
  Widget wrap(Widget child) => Tooltip(
        richMessage: WidgetSpan(child: _body()),
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        verticalOffset: 18,
        waitDuration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: C.paper,
          border: Border.all(color: C.line, width: 1.2),
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4)),
          ],
        ),
        child: child,
      );

  Widget _body() {
    final shown = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: IntrinsicWidth(
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kicker,
                  style: mono(size: 9, color: accent, w: FontWeight.w700)
                      .copyWith(letterSpacing: 1.1)),
              const SizedBox(height: 3),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: C.ink, height: 1.25)),
              if (shown.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(height: 1, color: C.line),
                const SizedBox(height: 7),
                for (final (label, value) in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 64,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(label.toUpperCase(),
                              style: mono(size: 8.5, color: C.ink3, w: FontWeight.w700)
                                  .copyWith(letterSpacing: .6)),
                        ),
                      ),
                      Flexible(
                        child: Text(value,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: C.ink2, height: 1.3)),
                      ),
                    ]),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
