import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This device's identity for sync: a stable random id plus a human label the
/// user can rename ("Oliver's PC", "Kira's iPhone"). Both live in local prefs —
/// they identify the *device*, so they must never travel in the synced blob.
class Device {
  static const _kId = 'device_id';
  static const _kName = 'device_name';

  static String id = '';
  static String name = 'This device';

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    var saved = p.getString(_kId);
    if (saved == null || saved.isEmpty) {
      saved = 'd${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '${Random().nextInt(1 << 20).toRadixString(36)}';
      await p.setString(_kId, saved);
    }
    id = saved;
    name = p.getString(_kName) ?? defaultName();
  }

  static Future<void> rename(String n) async {
    final v = n.trim();
    if (v.isEmpty) return;
    name = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, v);
  }

  /// A friendly guess from the platform, used until the user renames it.
  static String defaultName() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => kIsWeb ? 'iPhone (web)' : 'iPhone',
        TargetPlatform.android => kIsWeb ? 'Android (web)' : 'Android phone',
        TargetPlatform.macOS => 'Mac',
        TargetPlatform.windows => 'Windows PC',
        TargetPlatform.linux => 'Linux PC',
        _ => 'This device',
      };
}
