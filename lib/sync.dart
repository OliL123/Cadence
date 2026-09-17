import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      _readMeta(data);
      // On an exact tie the two devices disagree with no clock to separate them;
      // defer to whichever one the user nominated as the main device.
      final tieGoesToCloud = remoteTs == store.updatedAt &&
          mainDeviceId != null &&
          !isMainDevice &&
          lastDeviceId == mainDeviceId;
      if (remoteTs > store.updatedAt || tieGoesToCloud) {
        // Cloud is newer — take it (per-task merge may keep some local edits).
        store.applyRemoteState(_appState(data));
        _lastSyncedJson = jsonEncode(store.exportState());
        lastSyncedAt = DateTime.now();
        if (store.pendingMergePush) {
          store.pendingMergePush = false;
          await _push(force: true); // push the corrected merge back up
        }
      } else if (store.updatedAt > remoteTs) {
        // We genuinely hold newer edits — publish them.
        await _push(force: true);
      }
      // Equal clocks and nothing to arbitrate: leave the cloud alone. Pushing
      // here is what let a stale device overwrite good cloud data.
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
            final remoteTs = (data['updatedAt'] ?? 0) as int;
            _readMeta(data);
            // Our own write coming back, or an older one — nothing to apply,
            // but keep the "who wrote last" labels fresh.
            if (remoteTs <= store.updatedAt) {
              notifyListeners();
              return;
            }
            store.applyRemoteState(_appState(data));
            _lastSyncedJson = jsonEncode(store.exportState());
            lastSyncedAt = DateTime.now();
            if (store.pendingMergePush) {
              store.pendingMergePush = false;
              _push(force: true); // push the corrected merge back up
            }
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
    final uid = _sb.auth.currentUser!.id;
    final json = jsonEncode(store.exportState());
    if (!force && json == _lastSyncedJson) return; // nothing new
    try {
      // Read before write: the upsert replaces the whole row, so without this
      // check a device holding older state could wipe newer cloud data.
      final row =
          await _sb.from(_table).select('data').eq('user_id', uid).maybeSingle();
      final remote = row?['data'];
      if (remote is Map) {
        final data = Map<String, dynamic>.from(remote);
        final remoteTs = (data['updatedAt'] ?? 0) as int;
        if (remoteTs > store.updatedAt) {
          // The cloud moved ahead while we were composing this push — adopt it
          // instead of clobbering. Our own edits survive via the per-task merge.
          store.applyRemoteState(_appState(data));
          _readMeta(data);
          lastSyncedAt = DateTime.now();
          if (store.pendingMergePush) {
            // The merge kept edits the cloud doesn't have, so our state is now
            // the newest. Publish it — dropping it here would leave the two
            // devices diverged until the next unrelated local edit.
            store.pendingMergePush = false;
            await _overwriteCloud();
          } else {
            _lastSyncedJson = jsonEncode(store.exportState());
          }
          notifyListeners();
          return;
        }
      }
      await _sb.from(_table).upsert({
        'user_id': uid,
        'data': _payload(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      lastDeviceId = Device.id;
      lastDeviceName = Device.name;
      _lastSyncedJson = json;
      lastSyncedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // offline / transient — will retry on the next change
    }
  }

  /// Nominate this device as the main one: it wins clock ties, and every device
  /// shows its name. Also publishes this device's state so it becomes canonical.
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
    // A deliberate override: write even if the cloud looks newer.
    await _overwriteCloud();
    message = '${Device.name} pushed to the cloud';
    notifyListeners();
  }

  /// Unconditional write, bypassing the read-before-write guard. Only reached
  /// from the explicit "Use this device" override.
  Future<void> _overwriteCloud() async {
    try {
      await _sb.from(_table).upsert({
        'user_id': _sb.auth.currentUser!.id,
        'data': _payload(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      lastDeviceId = Device.id;
      lastDeviceName = Device.name;
      _lastSyncedJson = jsonEncode(store.exportState());
      lastSyncedAt = DateTime.now();
    } catch (err) {
      message = 'Push failed: $err';
    }
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
