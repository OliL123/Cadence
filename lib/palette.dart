import 'package:flutter/material.dart';

/// Two skins, one codebase. The active skin is chosen at BUILD time:
///   flutter build ... --dart-define=CHRONICLE=true
/// picks the Chronicle skin; with no flag you get the default Cadence skin.
///
/// Every colour below is a const conditional on [C.chronicle], so the whole
/// palette resolves at compile time — the Cadence build is byte-identical to
/// before, and no widget has to give up `const`.
///
///  - Cadence: retro Hong Kong cha-chaan-teng signboard (cream, red, green).
///  - Chronicle: Greek antiquity — marble ivory, Aegean cobalt, poppy red,
///    olive, sepia engraving; painting mastheads, contour columns, tarot.
class C {
  /// True when this build was compiled with `--dart-define=CHRONICLE=true`.
  static const chronicle = bool.fromEnvironment('CHRONICLE');

  // ---- grounds ---------------------------------------------------------
  static const paper = chronicle ? Color(0xFFECE5D4) : Color(0xFFECE0C0); // ground / marble
  static const paper2 = chronicle ? Color(0xFFF7F1E2) : Color(0xFFF6EFDA); // card
  static const paper3 = chronicle ? Color(0xFFE2D8C1) : Color(0xFFE3D5B2); // inset

  // ---- inks ------------------------------------------------------------
  static const ink = chronicle ? Color(0xFF1F232B) : Color(0xFF2C271C);
  static const ink2 = chronicle ? Color(0xFF5B6371) : Color(0xFF6A6247);
  static const ink3 = chronicle ? Color(0xFF8B919C) : Color(0xFF978C6C);
  static const line = chronicle ? Color(0xFFD3CBB6) : Color(0xFFD6C79E);

  // ---- signboard colours ----------------------------------------------
  // Roles are preserved across skins so every widget keeps working:
  //   red     — primary accent / priority / overdue        → poppy red in Chronicle
  //   green   — secondary structure (panel edges, toggles)  → Aegean cobalt in Chronicle
  //   greenD  — darker secondary (dark text/fills)          → deep cobalt in Chronicle
  //   navy    — tertiary jewel (sort, dates, calendar)      → mid cobalt in Chronicle
  //   mustard — highlight (stars→olive sprig, add, streak)  → gold in Chronicle
  //   teal    — a distinct group default colour             → olive in Chronicle
  static const red = chronicle ? Color(0xFFB1382C) : Color(0xFFBE3A2B);
  static const green = chronicle ? Color(0xFF173A63) : Color(0xFF1F6E4E);
  static const greenD = chronicle ? Color(0xFF102A49) : Color(0xFF12503A);
  static const navy = chronicle ? Color(0xFF2F5C8C) : Color(0xFF2C4C7C);
  static const mustard = chronicle ? Color(0xFFC2A24C) : Color(0xFFD2982E);
  static const teal = chronicle ? Color(0xFF5F6A3A) : Color(0xFF217A6E);
  static const creamTxt = chronicle ? Color(0xFFF7F1E2) : Color(0xFFF6EFDA);

  // ---- Chronicle-only Greek tokens ------------------------------------
  // (Harmless to reference in either build; only used behind `if (C.chronicle)`.)
  static const sea = Color(0xFF173A63); // Aegean cobalt
  static const seaD = Color(0xFF102A49);
  static const seaL = Color(0xFF2F5C8C);
  static const poppy = Color(0xFFB1382C);
  static const olive = Color(0xFF5F6A3A);
  static const gold = Color(0xFFC2A24C);
  static const etch = Color(0xFF6B5A44); // sepia engraving line (columns)
  static const plum = Color(0xFF7A5A86);
}
