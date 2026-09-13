// Renders the Chronicle app icon — an olive sprig (the same mark used for the
// focus/star button) in olive green with a gold berry, on Greek marble inside a
// fine gold rim — to PNGs at the sizes the web/PWA (and iOS home screen) need.
// Font-free (everything is drawn), so it needs no system font.
// Run with:  flutter test test/gen_icon_chronicle.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Greek palette (matches lib/palette.dart Chronicle tokens).
const _marble = Color(0xFFECE5D4);
const _marbleD = Color(0xFFD7CDB2);
const _olive = Color(0xFF5F6A3A);
const _oliveD = Color(0xFF474F29);
const _gold = Color(0xFFC2A24C);
const _goldD = Color(0xFF8A6A1E);

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
    canvas.drawColor(_marble, BlendMode.src);
    // faint marble vignette
    canvas.drawRect(
        Rect.fromLTWH(0, 0, s, s),
        Paint()
          ..shader = ui.Gradient.radial(c, s * 0.72,
              [_marble.withValues(alpha: 0), _marbleD.withValues(alpha: .65)]));
    // fine gold rim (scaled with k so the maskable safe-zone keeps it)
    canvas.drawCircle(
        c,
        s * 0.455 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _gold
          ..strokeWidth = s * 0.022 * k);
    canvas.drawCircle(
        c,
        s * 0.42 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _goldD.withValues(alpha: .55)
          ..strokeWidth = s * 0.006 * k);
  }

  _sprig(canvas, c, s * 0.0275 * k);
}

/// The olive sprig, ported from lib/chronicle.dart's _SprigPainter (design laid
/// out in a 22-wide box), centred on [ctr] with [u] pixels per design unit.
void _sprig(Canvas canvas, Offset ctr, double u) {
  canvas.save();
  // Design box ~22 wide × ~24 tall; its visual centre sits near (11, 13).
  canvas.translate(ctr.dx - 11 * u, ctr.dy - 13 * u);

  final stem = Paint()
    ..color = _olive
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7 * u
    ..strokeCap = StrokeCap.round;
  canvas.drawPath(
      Path()
        ..moveTo(11 * u, 23 * u)
        ..cubicTo(10 * u, 17 * u, 9 * u, 12.5 * u, 13 * u, 4.5 * u),
      stem);

  final leaf = Paint()..color = _olive;
  final leafEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.35 * u
    ..color = _oliveD.withValues(alpha: .6);
  void ell(double cx, double cy, double rx, double ry, double deg) {
    canvas.save();
    canvas.translate(cx * u, cy * u);
    canvas.rotate(deg * math.pi / 180);
    final r = Rect.fromCenter(center: Offset.zero, width: rx * 2 * u, height: ry * 2 * u);
    canvas.drawOval(r, leaf);
    canvas.drawOval(r, leafEdge);
    canvas.restore();
  }

  ell(6.6, 16, 3.1, 1.5, 32);
  ell(15, 12.5, 3.1, 1.5, -32);
  ell(7.6, 10.5, 2.7, 1.3, 38);
  ell(14.2, 7.6, 2.7, 1.3, -38);

  // gold olive at the tip
  canvas.drawCircle(Offset(13 * u, 4.4 * u), 2.2 * u, Paint()..color = _gold);
  canvas.drawCircle(
      Offset(13 * u, 4.4 * u),
      2.2 * u,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.45 * u
        ..color = _goldD);
  canvas.restore();
}
