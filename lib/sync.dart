import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'calendar/gcal.dart';
import 'device.dart';
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

  // Who last wrote the cloud copy, and which device the user nominated as the
  // main one. These ride along inside the blob but are NOT part of the app
  // state — `store.applyState` ignores unknown keys, so they never clobber data.
  String? lastDeviceId;
  String? lastDeviceName;
  String? mainDeviceId;
  String? mainDeviceName;

  String? get email => _sb.auth.currentUser?.email;
  bool get isSignedIn => _sb.auth.currentUser != null;
  bool get isMainDevice => mainDeviceId != null && mainDeviceId == Device.id;
  bool get lastWriteWasThisDevice => lastDeviceId == Device.id;

  /// The state we upload: the app state plus device bookkeeping.
  Map<String, dynamic> _payload() => {
        ...store.exportState(),
        'lastDev': Device.id,
        'lastDevName': Device.name,
        if (mainDeviceId != null) 'mainDev': mainDeviceId,
        if (mainDeviceName != null) 'mainDevName': mainDeviceName,
      };

  /// View preferences used to live in the synced blob, so rows written by older
  /// builds still carry them. Strip them on the way in: which filter or layout
  /// a device is showing must never be dictated by another device.
  static const _viewKeys = {
    'viewMode',
    'sortMode',
    'filter',
    'showDone',
    'headerCollapsed',
    'hideEmptyGroups',
  };

  Map<String, dynamic> _appState(Map<String, dynamic> data) =>
      Map<String, dynamic>.from(data)
        ..removeWhere((k, _) => _viewKeys.contains(k));

  void _readMeta(Map<String, dynamic> data) {
    lastDeviceId = data['lastDev'] as String?;
    lastDeviceName = data['lastDevName'] as String?;
    mainDeviceId = data['mainDev'] as String?;
    mainDeviceName = data['mainDevName'] as String?;
  }

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
  /// New accounts need a longer password than Supabase's default minimum.
  static const minPasswordLength = 10;

  void _fail(String msg) {
    stage = SyncStage.error;
    message = msg;
    notifyListeners();
  }

  /// Sign in to an existing account (email + password; no email delivery).
  /// Signing in never creates an account — a mistyped email used to quietly
  /// make a new, empty one — and a failure doesn't say whether the email is
  /// registered.
  Future<void> signIn(String email, String password) async {
    final e = email.trim();
    if (e.isEmpty || password.isEmpty) return _fail('Enter your email and password.');
    stage = SyncStage.syncing;
    message = null;
    notifyListeners();
    try {
      await _sb.auth.signInWithPassword(email: e, password: password);
      // _onSignedIn runs via the auth-state listener.
    } on AuthException {
      _fail('Email or password is incorrect.');
    } catch (_) {
      _fail('Couldn\'t reach the sync server — check your connection.');
    }
  }

  /// Create a new account — a separate, deliberate step from signing in.
  Future<void> createAccount(String email, String password) async {
    final e = email.trim();
    if (e.isEmpty || !e.contains('@')) return _fail('Enter a valid email.');
    if (password.length < minPasswordLength) {
      return _fail('Use a password of at least $minPasswordLength characters.');
    }
    stage = SyncStage.syncing;
    message = null;
    notifyListeners();
    try {
      final res = await _sb.auth.signUp(email: e, password: password);
      if (res.session == null) {
        _fail('Account created, but it needs email confirmation before it can sign in.');
      }
      // else: signed in, the listener handles it.
    } on AuthException catch (err) {
      final m = err.message.toLowerCase();
      _fail(m.contains('not allowed') || m.contains('disabled')
          ? 'New accounts are closed on this app.'
          : m.contains('password')
              ? err.message
              : 'Couldn\'t create that account. If you already have one, sign in instead.');
    } catch (_) {
      _fail('Couldn\'t reach the sync server — check your connection.');
    }
  }

  /// Local edits the cloud hasn't received yet (e.g. made while offline).
  bool get hasUnsyncedChanges =>
      isSignedIn && jsonEncode(store.exportState()) != _lastSyncedJson;

  /// Sign out and remove your data from this device. It stays in your
  /// account; signing in again (here or anywhere) brings it back. Leaving it
  /// would show your tasks and Career to the next person using this browser.
  /// Pending edits are uploaded first so nothing is lost — and if that upload
  /// fails (offline), the device is NOT wiped: returns false and stays signed
  /// in, since the wipe would delete edits that exist nowhere else.
  Future<bool> signOut() async {
    _pushTimer?.cancel();
    if (isSignedIn && hasUnsyncedChanges && !await _push(force: true)) {
      message = 'Couldn\'t upload your latest changes, so you\'re still signed '
          'in. Try again when you\'re online.';
      notifyListeners();
      return false;
    }
    _teardown();
    await _sb.auth.signOut();
    await store.wipeDevice();
    await GCalService.instance.forgetOnDevice();
    message = null;
    notifyListeners();
    return true;
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
      _readMeta(data);
      // Always merge — never "whoever's clock is newer uploads everything".
      // That rule let a device that had just added one task (or a fresh,
      // signed-out one) replace the whole account with its own copy.
      store.applyRemoteState(_appState(data));
      lastSyncedAt = DateTime.now();
      await _publishMergeIfNeeded();
    } else {
      // First device for this account — nothing to merge with.
      await _upload();
    }
  }

  /// After a merge: upload it if this device contributed something the cloud
  /// copy lacks; otherwise just note that we're in step with the cloud.
  Future<void> _publishMergeIfNeeded() async {
    if (store.pendingMergePush) {
      store.pendingMergePush = false;
      await _upload();
    } else {
      _lastSyncedJson = jsonEncode(store.exportState());
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
            _readMeta(data);
            // Merge whatever arrives. Our own write echoing back merges to no
            // change; anything this device holds that the incoming copy lacks
            // (an edit made meanwhile) is uploaded again.
            store.applyRemoteState(_appState(data));
            lastSyncedAt = DateTime.now();
            _publishMergeIfNeeded().catchError((_) {}); // offline: next change retries
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

  /// Returns false if the upload failed (offline / transient).
  Future<bool> _push({bool force = false}) async {
    if (!isSignedIn) return false;
    final uid = _sb.auth.currentUser!.id;
    final json = jsonEncode(store.exportState());
    if (!force && json == _lastSyncedJson) return true; // nothing new
    try {
      // Read, merge, then write: the upsert replaces the whole row, so the
      // cloud's copy is folded in first and nothing it holds is lost — even
      // if another device wrote since we last looked.
      final row =
          await _sb.from(_table).select('data').eq('user_id', uid).maybeSingle();
      final remote = row?['data'];
      if (remote is Map) {
        final data = Map<String, dynamic>.from(remote);
        _readMeta(data);
        store.applyRemoteState(_appState(data));
        lastSyncedAt = DateTime.now();
        await _publishMergeIfNeeded();
      } else {
        await _upload();
      }
      notifyListeners();
      return true;
    } catch (_) {
      // offline / transient — will retry on the next change
      return false;
    }
  }

  /// Nominate this device as the main one. It's a label only — every device
  /// shows its name — and gives no priority: sync merges item by item, newest
  /// edit wins, whichever device made it. Also publishes this device's state.
  Future<void> setMainDevice() async {
    if (!isSignedIn) return;
    mainDeviceId = Device.id;
    mainDeviceName = Device.name;
    store.touch();
    await _push(force: true);
    message = '${Device.name} is now the main device';
    notifyListeners();
  }

  /// Rename this device and republish so other devices see the new label.
  Future<void> renameDevice(String name) async {
    await Device.rename(name);
    if (mainDeviceId == Device.id) mainDeviceName = Device.name;
    if (isSignedIn) await _push(force: true);
    notifyListeners();
  }

  /// On app resume, re-read local state (a home-screen widget tap may have
  /// changed it) then merge with the cloud — never a blind push, so a stale
  /// local copy can't clobber newer cloud data.
  Future<void> onResume() async {
    await store.load();
    store.notify();
    if (isSignedIn) await _pull();
  }

  /// "Sync now": merge with the cloud and upload anything it's missing,
  /// reporting the result. (This replaced a "Use this device" override:
  /// with merging sync, other devices would just merge their items back.)
  Future<void> syncNow() async {
    if (!isSignedIn) return;
    try {
      await _pull();
      message = 'Up to date';
    } catch (_) {
      message = 'Couldn\'t reach the sync server — check your connection.';
    }
    notifyListeners();
  }

  /// Write this device's state to the cloud row. Callers merge first; throws
  /// when offline.
  Future<void> _upload() async {
    // Snapshot the payload and its score together: the score marked synced
    // must be exactly the one uploaded.
    final payload = _payload();
    final pushedScore = store.score;
    final json = jsonEncode(store.exportState());
    await _sb.from(_table).upsert({
      'user_id': _sb.auth.currentUser!.id,
      'data': payload,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    store.markScoreSynced(pushedScore);
    lastDeviceId = Device.id;
    lastDeviceName = Device.name;
    _lastSyncedJson = json;
    lastSyncedAt = DateTime.now();
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
        _readMeta(data);
        store.applyRemoteState(_appState(data), merge: false); // manual override: cloud wins outright
        _lastSyncedJson = jsonEncode(store.exportState());
        lastSyncedAt = DateTime.now();
        message = 'Loaded the cloud copy'
            '${lastDeviceName != null ? ' from $lastDeviceName' : ''}';
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
