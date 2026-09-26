import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  // Whether the signed-in user has a refresh token stored by the gcal-token
  // function. The token itself never lives on the device.
  static const _kServerLinked = 'gcal_server_linked';

  GCalStage stage = GCalStage.idle;
  String? message;
  String? _token;
  DateTime? _tokenExp;
  List<GCalCalendar> calendars = []; // full list from the account
  List<GCalEvent> events = []; // upcoming events from the selected calendars
  // The chosen sub-calendars live in the synced store (store.gcalCalendars) so
  // the selection persists and follows you across devices.

  bool _wantConnected = false;
  bool _serverLinked = false;
  bool _serverReady = false; // gcal-token function deployed with its secrets
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _observerWired = false;

  bool get _tokenValid =>
      _token != null &&
      _tokenExp != null &&
      _tokenExp!.isAfter(DateTime.now().add(const Duration(minutes: 1)));

  bool get _signedIn {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false; // Supabase unavailable (offline start / not configured)
    }
  }

  /// Web can use the server-held refresh token: the function is live and we
  /// know who the user is.
  bool get _canUseServer => !auth.silentTokenIsReallySilent && _serverReady && _signedIn;

  /// Whether access can be renewed with no UI at all. Native sign-in always
  /// can; the web only via the server.
  bool get staysConnected =>
      auth.silentTokenIsReallySilent || (_canUseServer && _serverLinked);

  /// The lasting connection is available but needs a Sync account to hang the
  /// refresh token on — worth a nudge in the calendar card.
  bool get needsSyncForLastingLink =>
      !auth.silentTokenIsReallySilent && _serverReady && !_signedIn;

  bool get supported => auth.gcalAuthSupported;
  bool get isConnected => stage == GCalStage.connected;
  bool get isBusy => stage == GCalStage.connecting;

  /// Linked before, but not live now — the card offers a Reconnect button.
  /// Nothing reconnects by itself in this state: no automatic popups, ever.
  bool get needsReconnect => _wantConnected && !isConnected && !isBusy;
  List<String> get selectedIds => store.gcalCalendars;

  /// Load saved prefs. Reuse a still-valid cached token, or renew silently
  /// where that's genuinely silent. Never opens Google's popup on its own.
  /// The calendar *selection* lives in the synced store, not here.
  Future<void> init() async {
    if (!_observerWired) {
      WidgetsBinding.instance.addObserver(this);
      _observerWired = true;
    }
    final p = await SharedPreferences.getInstance();
    _wantConnected = p.getBool(_kConnected) ?? false;
    _serverLinked = p.getBool(_kServerLinked) ?? false;
    await p.remove('gcal_auto_paused'); // superseded by server refresh tokens
    final savedTok = p.getString(_kToken);
    final savedExp = p.getInt(_kTokenExp);
    if (savedTok != null && savedExp != null) {
      _token = savedTok;
      _tokenExp = DateTime.fromMillisecondsSinceEpoch(savedExp);
    }
    // Know whether the server path exists before deciding how to renew.
    if (!auth.silentTokenIsReallySilent) await _probeServer();
    if (!supported || !_wantConnected) return;
    if (_tokenValid) {
      _scheduleRefresh();
      unawaited(_afterAuth());
    } else {
      unawaited(_reconnect());
    }
  }

  Future<void> _probeServer() async {
    try {
      final r = await Supabase.instance.client.functions
          .invoke('gcal-token', body: {'action': 'ping'})
          .timeout(const Duration(seconds: 6));
      final d = r.data;
      _serverReady = d is Map && d['configured'] == true;
    } catch (_) {
      _serverReady = false; // not deployed yet, or offline
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kConnected, _wantConnected);
    await p.setBool(_kServerLinked, _serverLinked);
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

  /// Renew ~2 min before expiry — only when that can happen with no UI.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (_tokenExp == null || !staysConnected) return;
    final lead = _tokenExp!
        .subtract(const Duration(minutes: 2))
        .difference(DateTime.now());
    // After a sleep the timer fires late; renew straight away then.
    final delay = lead.isNegative ? const Duration(seconds: 3) : lead;
    _refreshTimer = Timer(delay, () => unawaited(_silentRefresh()));
  }

  /// Renew the access token without any UI, or do nothing. On the web that
  /// means asking the gcal-token function to use the stored refresh token;
  /// natively google_sign_in renews itself. Google's "silent" web request is
  /// never used from here: it opens a popup, which is what made the app ask
  /// to link Google every time a laptop woke from sleep.
  Future<bool> _silentRefresh() async {
    if (_refreshing) return false;
    _refreshing = true;
    try {
      (String, int)? t;
      if (auth.silentTokenIsReallySilent) {
        t = await auth.getCalendarToken(interactive: false);
      } else if (_canUseServer && _serverLinked) {
        t = await _refreshViaServer();
      }
      if (t == null) return false;
      _storeToken(t);
      await _save();
      return true;
    } finally {
      _refreshing = false;
    }
  }

  Future<(String, int)?> _refreshViaServer() async {
    try {
      return _tokenFrom(await _call({'action': 'refresh'}));
    } on _Rejected {
      // Revoked, or Google's 7-day limit while the consent screen is in
      // Testing. Nothing to renew from any more — wait for a manual Reconnect.
      _serverLinked = false;
      await _save();
      return null;
    } catch (_) {
      return null; // offline / transient: keep the link and retry later
    }
  }

  (String, int)? _tokenFrom(Map<String, dynamic> d) {
    final tok = d['access_token'];
    if (tok is! String || tok.isEmpty) return null;
    return (tok, (d['expires_in'] as num?)?.toInt() ?? 3600);
  }

  /// Calls the gcal-token function as the signed-in user. Throws [_Rejected]
  /// when the stored grant is definitively gone; other failures throw as-is.
  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final r = await Supabase.instance.client.functions
          .invoke('gcal-token', body: body)
          .timeout(const Duration(seconds: 12));
      final d = r.data;
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } on FunctionException catch (e) {
      final det = e.details;
      final err = det is Map ? det['error'] : null;
      if (err == 'invalid_grant' || err == 'no_refresh_token') {
        throw _Rejected(err as String);
      }
      rethrow;
    }
  }

  Future<void> _reconnect() async {
    if (!await _silentRefresh()) return; // stay idle; Reconnect button shows
    await _afterAuth();
  }

  Future<void> connect() async {
    if (!supported) {
      _fail('Google sign-in isn’t available on this platform yet.');
      return;
    }
    stage = GCalStage.connecting;
    message = null;
    notifyListeners();

    (String, int)? t;
    if (_canUseServer) {
      // Code flow: the function exchanges it and keeps the refresh token, so
      // this is the last time Google has to ask.
      final code = await auth.getCalendarCode();
      if (code == null) return _fail('Sign-in was cancelled.');
      try {
        t = _tokenFrom(await _call({'action': 'exchange', 'code': code}));
      } on _Rejected {
        return _fail(
            'Google didn’t grant lasting access that time — tap Connect once more.');
      } catch (_) {
        return _fail('Couldn’t reach the sign-in service. Try again.');
      }
      if (t == null) return _fail('Couldn’t finish connecting to Google. Try again.');
      _serverLinked = true;
    } else {
      // Native (renews itself), or the web before the server is set up /
      // while signed out of Sync (lasts about an hour, then Reconnect).
      t = await auth.getCalendarToken(interactive: true);
      if (t == null) return _fail('Sign-in was cancelled.');
    }
    _wantConnected = true;
    _storeToken(t);
    await _save();
    await _afterAuth();
  }

  void _fail(String msg) {
    stage = GCalStage.error;
    message = msg;
    notifyListeners();
  }

  /// Back in the foreground (a laptop waking, a PWA reopened): if the token
  /// lapsed meanwhile, renew it — silently, or not at all.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!supported || !_wantConnected) return;
    if (_tokenValid) {
      if (isConnected) unawaited(refreshEvents());
      return;
    }
    if (!staysConnected) return; // nothing silent to do; Reconnect is shown
    unawaited(_silentRefresh().then((ok) {
      if (ok) unawaited(_afterAuth());
    }));
  }

  Future<void> disconnect() async {
    _refreshTimer?.cancel();
    if (_serverLinked && _canUseServer) {
      try {
        await _call({'action': 'revoke'});
      } catch (_) {} // best effort; the local unlink below still happens
    }
    _serverLinked = false;
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
        if (!_isHolidayCalendar(it['id'] as String))
          GCalCalendar(
            it['id'] as String,
            (it['summaryOverride'] ?? it['summary'] ?? it['id']) as String,
            _parseColor(it['backgroundColor'] as String?),
          )
    ];
  }

  /// Google publishes its own "Holidays in …" calendars. The app has a
  /// dedicated holidays/feasts section, so offering them here just duplicates
  /// it — hide them from the picker and ignore them when fetching events.
  static bool _isHolidayCalendar(String id) =>
      id.contains('#holiday@') || id.contains('holiday@group.v.calendar.google.com');

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
      // A selection made before holiday calendars were hidden can still name
      // one; don't fetch it, or its events would reappear in Upcoming.
      if (calendars.isNotEmpty && !byId.containsKey(id)) continue;
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

/// The server has no usable grant for this user (revoked, expired, or Google
/// withheld the refresh token) — only a manual Reconnect can fix it.
class _Rejected implements Exception {
  final String reason;
  _Rejected(this.reason);
}
