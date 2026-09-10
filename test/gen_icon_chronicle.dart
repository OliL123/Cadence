// Renders the Chronicle app icon — a deep-red wax seal with a gold ring and a
// cream "C" on parchment — to PNGs at the sizes the web/PWA (and iOS home
// screen) need. Font-free (the C is drawn), so it needs no system font.
// Run with:  flutter test test/gen_icon_chronicle.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _parch = Color(0xFFE7DFC9);
const _parchD = Color(0xFFD8CBAA);
const _red = Color(0xFF9E2420);
const _redD = Color(0xFF6E1512);
const _gold = Color(0xFFC7A24A);
const _goldD = Color(0xFF8A6A1E);
const _cream = Color(0xFFF4EEDA);

const _outDir = r'C:\src\cadence\tool\chronicle_icons';

void main() {
  testWidgets('generate chronicle icon', (tester) async {
    Directory(_outDir).createSync(recursive: true);

    Future<void> render(String name, int px, {required bool withBg, double scale = 1.0}) async {
      final s = px.toDouble();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Rect.fromLTWH(0, 0, s, s));
      _draw(canvas, s, withBg, scale);
      final img = await rec.endRecording().toImage(px, px);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir\\$name').writeAsBytesSync(png!.buffer.asUint8List());
    }

    // master + web/PWA/iOS sizes (full, opaque — iOS masks its own corners)
    await render('ic_full.png', 1024, withBg: true);
    await render('Icon-512.png', 512, withBg: true);
    await render('Icon-192.png', 192, withBg: true);
    await render('apple-touch-icon.png', 180, withBg: true);
    await render('favicon.png', 64, withBg: true);
    // maskable (Android adaptive-safe: emblem pulled into the safe zone)
    await render('Icon-maskable-512.png', 512, withBg: true, scale: 0.78);
    await render('Icon-maskable-192.png', 192, withBg: true, scale: 0.78);
    // Android adaptive foreground (transparent)
    await render('ic_fg.png', 1024, withBg: false, scale: 0.80);
  });
}

void _draw(Canvas canvas, double s, bool withBg, double k) {
  final c = Offset(s / 2, s / 2);

  if (withBg) {
    canvas.drawColor(_parch, BlendMode.src);
    // faint parchment vignette
    canvas.drawRect(
        Rect.fromLTWH(0, 0, s, s),
        Paint()
          ..shader = ui.Gradient.radial(c, s * 0.72,
              [_parch.withValues(alpha: 0), _parchD.withValues(alpha: .7)]));
  }

  // red wax seal disc with a soft darker rim
  final disc = s * 0.40 * k;
  canvas.drawCircle(
      c, disc, Paint()..shader = ui.Gradient.radial(
          Offset(c.dx - disc * .25, c.dy - disc * .25), disc * 1.25, [_red, _redD]));

  // gold double ring
  canvas.drawCircle(c, disc * 0.965,
      Paint()..style = PaintingStyle.stroke..color = _gold..strokeWidth = s * 0.028 * k);
  canvas.drawCircle(c, disc * 0.83,
      Paint()..style = PaintingStyle.stroke..color = _goldD..strokeWidth = s * 0.012 * k);

  // cream "C" monogram (drawn arc over a slightly wider gold arc, no blur —
  // MaskFilter.blur stalls the headless test rasteriser)
  final rad = disc * 0.5;
  final under = Paint()
    ..style = PaintingStyle.stroke
    ..color = _gold
    ..strokeWidth = s * 0.11 * k
    ..strokeCap = StrokeCap.round;
  final ink = Paint()
    ..style = PaintingStyle.stroke
    ..color = _cream
    ..strokeWidth = s * 0.075 * k
    ..strokeCap = StrokeCap.round;
  final arcRect = Rect.fromCircle(center: c, radius: rad);
  canvas.drawArc(arcRect, 0.32 * math.pi, 1.36 * math.pi, false, under);
  canvas.drawArc(arcRect, 0.32 * math.pi, 1.36 * math.pi, false, ink);
}
