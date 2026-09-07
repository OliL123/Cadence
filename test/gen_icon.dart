// Renders the Cadence app icon (circular pawn-shop emblem with 節奏) to PNGs,
// using a Windows CJK serif font so the characters render. Run with:
//   flutter test test/gen_icon.dart
// then generate launcher icons with flutter_launcher_icons.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = Color(0xFFBE3A2B);
const _redDark = Color(0xFF8E2418);
const _jade = Color(0xFF34C79E);
const _cream = Color(0xFFF6EFDA);
const _gold = Color(0xFFE7B24A);

void main() {
  testWidgets('generate app icon', (tester) async {
    // Load a CJK serif font from Windows so 節奏 renders.
    final bytes = File(r'C:\Windows\Fonts\NotoSerifSC-VF.ttf').readAsBytesSync();
    final loader = FontLoader('IconCJK')
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();

    Future<void> render(String path, {required bool withBg, double scale = 1.0}) async {
      const s = 1024.0;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, s, s));
      _draw(canvas, s, withBg, scale);
      final img = await rec.endRecording().toImage(s.toInt(), s.toInt());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(png!.buffer.asUint8List());
    }

    // Legacy / full icon (red plaque baked in).
    await render(r'C:\src\cadence\assets\icon\ic_full.png', withBg: true);
    // Adaptive foreground: transparent, emblem scaled into the safe zone.
    await render(r'C:\src\cadence\assets\icon\ic_fg.png', withBg: false, scale: 0.80);
  });
}

void _draw(Canvas canvas, double s, bool withBg, double k) {
  final c = Offset(s / 2, s / 2);

  if (withBg) {
    // full red plaque with a soft darker vignette toward the edges
    canvas.drawColor(_red, BlendMode.src);
    final vignette = Paint()
      ..shader = ui.Gradient.radial(c, s * 0.72, [
        _red.withValues(alpha: 0),
        _redDark.withValues(alpha: .55),
      ]);
    canvas.drawRect(Rect.fromLTWH(0, 0, s, s), vignette);
  }

  // green neon double-ring
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..color = _jade
    ..strokeWidth = s * 0.034 * k;
  canvas.drawCircle(c, s * 0.40 * k, ring);
  final ring2 = Paint()
    ..style = PaintingStyle.stroke
    ..color = _jade
    ..strokeWidth = s * 0.015 * k;
  canvas.drawCircle(c, s * 0.345 * k, ring2);

  // 節奏 — two characters side by side
  final tp = TextPainter(
    text: TextSpan(
      text: '節奏',
      style: TextStyle(
        fontFamily: 'IconCJK',
        fontSize: s * 0.30 * k,
        height: 1.0,
        fontWeight: FontWeight.w900,
        color: _cream,
        shadows: [
          Shadow(color: _gold.withValues(alpha: .9), blurRadius: s * 0.006),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
}
