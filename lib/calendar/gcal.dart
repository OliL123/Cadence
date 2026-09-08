import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Platform-split OAuth: real GIS token on web, no-op on mobile (for now).
import 'gcal_auth_stub.dart' if (dart.library.js_interop) 'gcal_auth_web.dart' as auth;

enum GCalStage { idle, connecting, connected, error }

class GCalCalendar {
  final String id;
  final String summary;
  final Color color;
  GCalCalendar(this.id, this.summary, this.color);
}

class GCalEvent {
  final String title;
  final DateTime start;
  final bool allDay;
  final Color color;
  GCalEvent(this.title, this.start, this.allDay, this.color);
}

/// Read-only Google Calendar. Web-only for now (mobile needs a native OAuth
/// client, added later). Keeps its own local prefs — deliberately NOT part of
/// the synced store, since the OAuth token is per-device.
class GCalService extends ChangeNotifier {
  GCalService._();
  static final GCalService instance = GCalService._();

  static const _kConnected = 'gcal_connected';
  static const _kSelected = 'gcal_selected';

  GCalStage stage = GCalStage.idle;
  String? message;
  String? _token;
  List<GCalCalendar> calendars = []; // full list from the account
  List<GCalEvent> events = []; // upcoming events from the selected calendars
  List<String> _selected = []; // selected calendar ids

  bool _wantConnected = false;

  bool get supported => auth.gcalAuthSupported;
  bool get isConnected => stage == GCalStage.connected;
  bool get isBusy => stage == GCalStage.connecting;
  List<String> get selectedIds => _selected;

  /// Load saved prefs and, if the user connected before, try a silent reconnect.
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _wantConnected = p.getBool(_kConnected) ?? false;
    final raw = p.getString(_kSelected);
    if (raw != null) {
      try {
        _selected = (jsonDecode(raw) as List).map((e) => e as String).toList();
      } catch (_) {}
    }
    if (supported && _wantConnected) {
      // silent, non-blocking
      unawaited(_reconnect());
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kConnected, _wantConnected);
    await p.setString(_kSelected, jsonEncode(_selected));
  }

  Future<void> _reconnect() async {
    final t = await auth.getCalendarToken(interactive: false);
    if (t == null) return; // stay idle; the Connect button remains
    _token = t;
    await _afterAuth();
  }

  Future<void> connect() async {
    if (!supported) {
      stage = GCalStage.error;
      message = 'Google sign-in isn’t available on this platform yet.';
      notifyListeners();
      return;
    }
    stage = GCalStage.connecting;
    message = null;
    notifyListeners();
    final t = await auth.getCalendarToken(interactive: true);
    if (t == null) {
      stage = GCalStage.error;
      message = 'Sign-in was cancelled.';
      notifyListeners();
      return;
    }
    _token = t;
    _wantConnected = true;
    await _save();
    await _afterAuth();
  }

  Future<void> disconnect() async {
    _token = null;
    _wantConnected = false;
    calendars = [];
    events = [];
    stage = GCalStage.idle;
    message = null;
    await _save();
    notifyListeners();
  }

  Future<void> _afterAuth() async {
    try {
      await _loadCalendars();
      // Default: if the user hasn't chosen yet, show their primary calendar.
      if (_selected.isEmpty && calendars.isNotEmpty) {
        final primary = calendars.firstWhere((c) => c.id.contains('@'),
            orElse: () => calendars.first);
        _selected = [primary.id];
        await _save();
      }
      await refreshEvents();
      stage = GCalStage.connected;
      message = null;
    } catch (err) {
      stage = GCalStage.error;
      message = 'Couldn’t load your calendars.';
    }
    notifyListeners();
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer $_token'};

  Future<void> _loadCalendars() async {
    final r = await http.get(
      Uri.parse('https://www.googleapis.com/calendar/v3/users/me/calendarList'),
      headers: _headers,
    );
    if (r.statusCode != 200) throw 'calendarList ${r.statusCode}';
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final items = (j['items'] ?? []) as List;
    calendars = [
      for (final it in items)
        GCalCalendar(
          it['id'] as String,
          (it['summaryOverride'] ?? it['summary'] ?? it['id']) as String,
          _parseColor(it['backgroundColor'] as String?),
        )
    ];
  }

  bool isSelected(String id) => _selected.contains(id);

  Future<void> toggleCalendar(String id) async {
    if (_selected.contains(id)) {
      _selected = _selected.where((x) => x != id).toList();
    } else {
      _selected = [..._selected, id];
    }
    await _save();
    notifyListeners();
    await refreshEvents();
  }

  Future<void> refreshEvents() async {
    if (_token == null) return;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final timeMin = start.toUtc().toIso8601String();
    final timeMax = start.add(const Duration(days: 21)).toUtc().toIso8601String();
    final byId = {for (final c in calendars) c.id: c};
    final out = <GCalEvent>[];
    for (final id in _selected) {
      final color = byId[id]?.color ?? const Color(0xFF2C4C7C);
      final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(id)}/events'
          '?timeMin=$timeMin&timeMax=$timeMax&singleEvents=true&orderBy=startTime&maxResults=20');
      try {
        final r = await http.get(uri, headers: _headers);
        if (r.statusCode != 200) continue;
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        for (final it in (j['items'] ?? []) as List) {
          final s = it['start'] as Map<String, dynamic>?;
          if (s == null) continue;
          final allDay = s['date'] != null;
          final dt = allDay
              ? DateTime.parse(s['date'] as String)
              : DateTime.parse(s['dateTime'] as String).toLocal();
          out.add(GCalEvent(
              (it['summary'] ?? '(no title)') as String, dt, allDay, color));
        }
      } catch (_) {}
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    events = out;
    notifyListeners();
  }

  Color _parseColor(String? hex) {
    if (hex == null) return const Color(0xFF2C4C7C);
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    if (v == null) return const Color(0xFF2C4C7C);
    return Color(0xFF000000 | v);
  }
}
