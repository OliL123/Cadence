import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'store.dart';

enum SyncStage { signedOut, syncing, live, error }

/// Cross-device sync over Supabase. Offline-first: the app works fully without
/// signing in; signing in mirrors the task state between this device and any
/// other device signed in with the same email.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _table = 'cadence_state';

  SupabaseClient get _sb => Supabase.instance.client;

  SyncStage stage = SyncStage.signedOut;
  String? message;
  DateTime? lastSyncedAt; // last successful push or pull

  Timer? _pushTimer;
  RealtimeChannel? _channel;
  String? _lastSyncedJson; // last payload we pushed or applied (echo guard)
  bool _wired = false;

  String? get email => _sb.auth.currentUser?.email;
  bool get isSignedIn => _sb.auth.currentUser != null;

  /// Call once after Supabase.initialize + store.load.
  void start() {
    _sb.auth.onAuthStateChange.listen((data) {
      if (_sb.auth.currentUser != null) {
        _onSignedIn();
      } else {
        _teardown();
        stage = SyncStage.signedOut;
        notifyListeners();
      }
    });
    if (isSignedIn) _onSignedIn();
  }

  // ---------- auth ----------
  /// One button for both cases: signs in if the account exists, otherwise
  /// creates it. Uses email + password (no email delivery needed).
  Future<void> connect(String email, String password) async {
    final e = email.trim();
    final p = password.trim();
    if (e.isEmpty || p.length < 6) {
      stage = SyncStage.error;
      message = 'Enter an email and a password (6+ characters).';
      notifyListeners();
      return;
    }
    stage = SyncStage.syncing;
    message = null;
    notifyListeners();
    try {
      // Existing account -> sign in.
      await _sb.auth.signInWithPassword(email: e, password: p);
      // _onSignedIn runs via the auth-state listener.
    } on AuthException catch (signInErr) {
      // Might be a new account -> try to create it.
      try {
        final res = await _sb.auth.signUp(email: e, password: p);
        if (res.session == null) {
          stage = SyncStage.error;
          message =
              'Turn off "Confirm email" in Supabase (Auth → Providers → Email), then try again.';
          notifyListeners();
        }
        // else: signed in, listener handles it.
      } on AuthException catch (signUpErr) {
        stage = SyncStage.error;
        message = signUpErr.message.contains('registered')
            ? 'Wrong password for this email.'
            : signInErr.message;
        notifyListeners();
      }
    }
  }

  Future<void> signOut() async {
    await _sb.auth.signOut();
  }

  // ---------- sync ----------
  Future<void> _onSignedIn() async {
    stage = SyncStage.syncing;
    message = null;
    notifyListeners();
    try {
      await _pull();
      _subscribe();
      if (!_wired) {
        store.addListener(_onLocalChange);
        _wired = true;
      }
      stage = SyncStage.live;
    } catch (err) {
      stage = SyncStage.error;
      message = 'Sync error: $err';
    }
    notifyListeners();
  }

  Future<void> _pull() async {
    final uid = _sb.auth.currentUser!.id;
    final row = await _sb
        .from(_table)
        .select('data')
        .eq('user_id', uid)
        .maybeSingle();
    if (row != null && row['data'] != null) {
      final data = Map<String, dynamic>.from(row['data'] as Map);
      final remoteTs = (data['updatedAt'] ?? 0) as int;
      if (remoteTs > store.updatedAt) {
        // Cloud is newer — take it.
        store.applyRemoteState(data);
        _lastSyncedJson = jsonEncode(store.exportState());
        lastSyncedAt = DateTime.now();
      } else {
        // Our local copy is newer (or equal) — push it up so the cloud matches.
        await _push(force: true);
      }
    } else {
      // First device for this account — seed the cloud with local state.
      await _push(force: true);
    }
  }

  void _subscribe() {
    final uid = _sb.auth.currentUser!.id;
    _channel?.unsubscribe();
    _channel = _sb
        .channel('cadence_state_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec['data'] == null) return;
            final data = Map<String, dynamic>.from(rec['data'] as Map);
            final incoming = jsonEncode(data);
            if (incoming == _lastSyncedJson) return; // our own echo
            final remoteTs = (data['updatedAt'] ?? 0) as int;
            if (remoteTs <= store.updatedAt) return; // stale — our copy is newer
            store.applyRemoteState(data);
            _lastSyncedJson = jsonEncode(store.exportState());
            lastSyncedAt = DateTime.now();
            notifyListeners();
          },
        )
        .subscribe();
  }

  void _onLocalChange() {
    if (!isSignedIn) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 700), () => _push());
  }

  Future<void> _push({bool force = false}) async {
    if (!isSignedIn) return;
    final json = jsonEncode(store.exportState());
    if (!force && json == _lastSyncedJson) return; // nothing new
    try {
      await _sb.from(_table).upsert({
        'user_id': _sb.auth.currentUser!.id,
        'data': store.exportState(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _lastSyncedJson = json;
      lastSyncedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // offline / transient — will retry on the next change
    }
  }

  /// On app resume, re-read local state (a home-screen widget tap may have
  /// changed it) then reconcile with the cloud by timestamp — never a blind
  /// push, so a stale local copy can't clobber newer cloud data.
  Future<void> onResume() async {
    await store.load();
    store.notify();
    if (isSignedIn) await _pull();
  }

  /// Manual override: force THIS device's data to win (stamps it newest, pushes).
  Future<void> forcePush() async {
    if (!isSignedIn) return;
    store.touch();
    await _push(force: true);
    message = 'This device pushed to the cloud';
    notifyListeners();
  }

  /// Manual override: replace local data with the cloud copy.
  Future<void> forcePull() async {
    if (!isSignedIn) return;
    try {
      final uid = _sb.auth.currentUser!.id;
      final row =
          await _sb.from(_table).select('data').eq('user_id', uid).maybeSingle();
      if (row != null && row['data'] != null) {
        final data = Map<String, dynamic>.from(row['data'] as Map);
        store.applyRemoteState(data);
        _lastSyncedJson = jsonEncode(store.exportState());
        message = 'Loaded the cloud copy';
      } else {
        message = 'No cloud data yet';
      }
    } catch (err) {
      message = 'Pull failed: $err';
    }
    notifyListeners();
  }

  void _teardown() {
    _channel?.unsubscribe();
    _channel = null;
    _pushTimer?.cancel();
  }
}
