import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../palette.dart';

// shared type styles — each resolves to the active skin's font at build time.
//  Cadence: Noto Serif HK (accent) / Oswald (display) / Space Mono (labels).
//  Chronicle: Playfair Display (accent + display) / EB Garamond (labels).
TextStyle serifHk({double size = 14, Color color = C.ink}) => C.chronicle
    ? GoogleFonts.cinzel(fontWeight: FontWeight.w600, fontSize: size, color: color)
    : GoogleFonts.notoSerifHk(fontWeight: FontWeight.w900, fontSize: size, color: color);
TextStyle disp({double size = 14, FontWeight w = FontWeight.w600, Color color = C.ink}) =>
    C.chronicle
        ? GoogleFonts.cinzel(fontSize: size, fontWeight: w, color: color)
        : GoogleFonts.oswald(fontSize: size, fontWeight: w, color: color);
TextStyle mono({double size = 11, Color color = C.ink3, FontWeight w = FontWeight.w400}) =>
    C.chronicle
        ? GoogleFonts.ebGaramond(fontSize: size, color: color, fontWeight: w)
        : GoogleFonts.spaceMono(fontSize: size, color: color, fontWeight: w);
