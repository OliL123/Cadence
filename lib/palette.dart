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
///  - Chronicle: classical antiquity — parchment, deep red silk, antique gold,
///    classical blue, illuminated ornament.
class C {
  /// True when this build was compiled with `--dart-define=CHRONICLE=true`.
  static const chronicle = bool.fromEnvironment('CHRONICLE');

  // ---- grounds ---------------------------------------------------------
  static const paper = chronicle ? Color(0xFFE7DFC9) : Color(0xFFECE0C0); // ground
  static const paper2 = chronicle ? Color(0xFFF3EDDA) : Color(0xFFF6EFDA); // card
  static const paper3 = chronicle ? Color(0xFFE0D6BD) : Color(0xFFE3D5B2); // inset

  // ---- inks ------------------------------------------------------------
  static const ink = chronicle ? Color(0xFF241F15) : Color(0xFF2C271C);
  static const ink2 = chronicle ? Color(0xFF6C6450) : Color(0xFF6A6247);
  static const ink3 = chronicle ? Color(0xFF9A8F74) : Color(0xFF978C6C);
  static const line = chronicle ? Color(0xFFCDBF9C) : Color(0xFFD6C79E);

  // ---- signboard colours ----------------------------------------------
  // Roles are preserved across skins so every widget keeps working:
  //   red     — primary accent / masthead edge / priority / overdue
  //   green   — secondary structure (panel edges, toggles, add field)  → antique gold in Chronicle
  //   greenD  — darker secondary (dark text on cream, darker fills)     → deep bronze in Chronicle
  //   navy    — tertiary jewel (sort, dates, calendar)                  → classical blue in Chronicle
  //   mustard — highlight (stars, add button, streak)                   → gilt in Chronicle
  //   teal    — a distinct group default colour                         → wine in Chronicle
  static const red = chronicle ? Color(0xFF9E2420) : Color(0xFFBE3A2B);
  static const green = chronicle ? Color(0xFF8A6A1E) : Color(0xFF1F6E4E);
  static const greenD = chronicle ? Color(0xFF5F4A14) : Color(0xFF12503A);
  static const navy = chronicle ? Color(0xFF2F4F8F) : Color(0xFF2C4C7C);
  static const mustard = chronicle ? Color(0xFFC99A34) : Color(0xFFD2982E);
  static const teal = chronicle ? Color(0xFF6B2737) : Color(0xFF217A6E);
  static const creamTxt = chronicle ? Color(0xFFF4EEDA) : Color(0xFFF6EFDA);

  // ---- Chronicle-only ornament tokens ---------------------------------
  // (Harmless to reference in either build; only used behind `if (C.chronicle)`.)
  static const gold = Color(0xFFB98F34);
  static const goldLit = Color(0xFFDCBB63);
  static const burg = Color(0xFF5F1622);
  static const night = Color(0xFF1B2340); // the spread cloth
  static const night2 = Color(0xFF10152A);
}
