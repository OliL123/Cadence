import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../store.dart';

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
class GCalService extends ChangeNotifier with WidgetsBindingObserver {
  GCalService._();
  static final GCalService instance = GCalService._();

  static const _kConnected = 'gcal_connected';
  static const _kToken = 'gcal_token';
  static const _kTokenExp = 'gcal_token_exp'; // ms-since-epoch expiry

  GCalStage stage = GCalStage.idle;
  String? message;
  String? _token;
  DateTime? _tokenExp;
  List<GCalCalendar> calendars = []; // full list from the account
  List<GCalEvent> events = []; // upcoming events from the selected calendars
  // The chosen sub-calendars live in the synced store (store.gcalCalendars) so
  // the selection persists and follows you across devices.

  bool _wantConnected = false;
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _observerWired = false;

  bool get _tokenValid =>
      _token != null &&
      _tokenExp != null &&
      _tokenExp!.isAfter(DateTime.now().add(const Duration(minutes: 1)));

  bool get supported => auth.gcalAuthSupported;
  bool get isConnected => stage == GCalStage.connected;
  bool get isBusy => stage == GCalStage.connecting;
  List<String> get selectedIds => store.gcalCalendars;

  /// Load saved prefs. Reuse a still-valid cached token (so a refresh doesn't
  /// re-prompt); otherwise try a silent reconnect if the user linked before.
  /// The calendar *selection* lives in the synced store, not here.
  Future<void> init() async {
    if (!_observerWired) {
      WidgetsBinding.instance.addObserver(this);
      _observerWired = true;
    }
    final p = await SharedPreferences.getInstance();
    _wantConnected = p.getBool(_kConnected) ?? false;
    final savedTok = p.getString(_kToken);
    final savedExp = p.getInt(_kTokenExp);
    if (savedTok != null && savedExp != null) {
      _token = savedTok;
      _tokenExp = DateTime.fromMillisecondsSinceEpoch(savedExp);
    }
    if (!supported || !_wantConnected) return;
    if (_tokenValid) {
      // Cached token is still good — go straight to connected, no popup.
      unawaited(_afterAuth());
    } else {
      unawaited(_reconnect());
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kConnected, _wantConnected);
    if (_token != null && _tokenExp != null) {
      await p.setString(_kToken, _token!);
      await p.setInt(_kTokenExp, _tokenExp!.millisecondsSinceEpoch);
    } else {
      await p.remove(_kToken);
      await p.remove(_kTokenExp);
    }
  }

  void _storeToken((String, int) tok) {
    _token = tok.$1;
    _tokenExp = DateTime.now().add(Duration(seconds: tok.$2));
    _scheduleRefresh();
  }

  /// Silently re-request the access token ~2 min before it expires, so a linked
  /// calendar stays live without the user ever seeing a popup or blank list.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (_tokenExp == null) return;
    final lead = _tokenExp!
        .subtract(const Duration(minutes: 2))
        .difference(DateTime.now());
    // Fire at least a few seconds out; if already past-due, fire soon.
    final delay = lead.isNegative ? const Duration(seconds: 3) : lead;
    _refreshTimer = Timer(delay, () => unawaited(_silentRefresh()));
  }

  /// Best-effort silent token refresh. Returns true if a fresh token was
  /// obtained. Used both by the pre-expiry timer and by 401 recovery.
  Future<bool> _silentRefresh() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      final t = await auth.getCalendarToken(interactive: false);
      if (t == null) return false;
      _storeToken(t);
      await _save();
      return true;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _reconnect() async {
    if (!await _silentRefresh()) return; // stay idle; the Connect button remains
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
    _storeToken(t);
    _wantConnected = true;
    await _save();
    await _afterAuth();
  }

  /// When the app comes back to the foreground (e.g. an iPhone PWA that was
  /// backgrounded for hours), the token has usually expired — refresh it and
  /// reload so the calendar isn't blank.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!supported || !_wantConnected) return;
    if (_tokenValid) {
      if (isConnected) unawaited(refreshEvents());
    } else {
      unawaited(_silentRefresh().then((ok) {
        if (ok) unawaited(_afterAuth());
      }));
    }
  }

  Future<void> disconnect() async {
    _refreshTimer?.cancel();
    _token = null;
    _tokenExp = null;
    _wantConnected = false;
    calendars = [];
    events = [];
    stage = GCalStage.idle;
    message = null;
    await _save();
    notifyListeners();
  }

  bool _storeWired = false;
  String _lastSelKey = '';

  Future<void> _afterAuth() async {
    try {
      await _loadCalendars();
      // Default: if the user hasn't chosen yet, show their primary calendar.
      // Quiet (no sync bump) so it can't clobber a selection syncing in.
      if (store.gcalCalendars.isEmpty && calendars.isNotEmpty) {
        final primary = calendars.firstWhere((c) => c.id.contains('@'),
            orElse: () => calendars.first);
        store.setGcalCalendarsQuiet([primary.id]);
      }
      await refreshEvents();
      stage = GCalStage.connected;
      message = null;
      // Refetch when the selection changes (e.g. it just synced from another
      // device) so events reflect it without needing a reload.
      if (!_storeWired) {
        store.addListener(_onStoreChanged);
        _storeWired = true;
      }
    } catch (err) {
      stage = GCalStage.error;
      message = 'Couldn’t load your calendars.';
    }
    notifyListeners();
  }

  void _onStoreChanged() {
    if (isConnected && store.gcalCalendars.join(',') != _lastSelKey) {
      refreshEvents();
    }
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer $_token'};

  /// GET with automatic silent-token recovery: on a 401 (expired/revoked
  /// token) it refreshes once and retries, so a stale token self-heals.
  Future<http.Response> _authedGet(Uri uri) async {
    var r = await http.get(uri, headers: _headers);
    if (r.statusCode == 401 && await _silentRefresh()) {
      r = await http.get(uri, headers: _headers);
    }
    return r;
  }

  Future<void> _loadCalendars() async {
    final r = await _authedGet(
      Uri.parse('https://www.googleapis.com/calendar/v3/users/me/calendarList'),
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

  bool isSelected(String id) => store.gcalCalendars.contains(id);

  Future<void> toggleCalendar(String id) async {
    final sel = store.gcalCalendars.toList();
    if (sel.contains(id)) {
      sel.remove(id);
    } else {
      sel.add(id);
    }
    store.setGcalCalendars(sel); // persists + syncs; _onStoreChanged refetches
    notifyListeners();
  }

  Future<void> refreshEvents() async {
    if (_token == null) return;
    _lastSelKey = store.gcalCalendars.join(','); // mark what we're fetching for
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final timeMin = start.toUtc().toIso8601String();
    final timeMax = start.add(const Duration(days: 21)).toUtc().toIso8601String();
    final byId = {for (final c in calendars) c.id: c};
    final out = <GCalEvent>[];
    for (final id in store.gcalCalendars) {
      final color = byId[id]?.color ?? const Color(0xFF2C4C7C);
      final uri = Uri.parse(
          'https://www.googleapis.com/calendar/v3/calendars/${Uri.encodeComponent(id)}/events'
          '?timeMin=$timeMin&timeMax=$timeMax&singleEvents=true&orderBy=startTime&maxResults=20');
      try {
        final r = await _authedGet(uri);
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
