// Masks the full square app icon (assets/icon/ic_full.png) into a circle,
// cutting the plaque corners to transparency, for use as the website favicon /
// PWA icons. Run with:  dart run tool/circle_favicon.dart
// then regenerate the web icons with:  dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/icon/ic_full.png').readAsBytesSync());
  if (src == null) {
    stderr.writeln('could not read assets/icon/ic_full.png');
    exit(1);
  }
  final w = src.width, h = src.height;
  final cx = w / 2.0, cy = h / 2.0;
  final r = math.min(w, h) / 2.0; // inscribed circle: keep the disc, drop corners
  final out = img.Image(width: w, height: h, numChannels: 4);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final p = src.getPixel(x, y);
      // 1.5px feathered edge so the circle looks smooth when scaled down.
      final edge = (r - dist).clamp(-1.5, 1.5);
      final a = ((edge + 1.5) / 3.0 * 255).round().clamp(0, 255);
      out.setPixelRgba(x, y, p.r, p.g, p.b, a);
    }
  }

  File('assets/icon/ic_circle.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('wrote assets/icon/ic_circle.png (${w}x$h, circular)');
}
