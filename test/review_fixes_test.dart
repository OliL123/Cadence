// Fixes from the 2026-10-09 goal review: Find's dismiss-undo survives sync,
// and only followed company boards get the "you follow them" ranking bonus.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/job_sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Posting posting(String key, String source) => Posting(
      key: key, source: source, company: 'Acme', title: 'Software Engineer Intern',
      locations: const ['New York, NY'], url: 'u', posted: DateTime.now());

  CadenceStore fresh() => CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});

  // What the cloud would hold: a JSON copy, as sync sends it — not the
  // store's own maps, which keep changing with it.
  Map<String, dynamic> copyOf(CadenceStore s) =>
      jsonDecode(jsonEncode(s.exportState())) as Map<String, dynamic>;

  group('dismiss-undo and sync', () {
    test('undo sticks when the cloud copy still has the dismissal', () {
      final s = fresh();
      final p = posting('simplify:1', 'simplify');
      s.dismissPosting(p);
      final cloud = copyOf(s); // synced within a second
      s.undismissPosting(p.key); // UNDO a few seconds later
      s.applyRemoteState(cloud);
      expect(s.findDismissed, isNot(contains(p.key)), reason: 'the merge must not bring it back');
      expect(s.pendingMergePush, isTrue, reason: 'the cloud still has it, so it needs the undo');
    });

    test('dismissing again later wins over an old undo', () async {
      final s = fresh();
      final p = posting('simplify:1', 'simplify');
      s.dismissPosting(p);
      s.undismissPosting(p.key);
      final cloud = copyOf(s); // has the undo marker
      await Future<void>.delayed(const Duration(milliseconds: 5));
      s.dismissPosting(p);
      s.applyRemoteState(cloud);
      expect(s.findDismissed, contains(p.key));
    });

    test('another device\'s undo reaches this one', () {
      final a = fresh();
      final p = posting('simplify:1', 'simplify');
      a.dismissPosting(p);
      final b = fresh()..applyRemoteState(copyOf(a));
      expect(b.findDismissed, contains(p.key));
      a.undismissPosting(p.key);
      b.applyRemoteState(copyOf(a));
      expect(b.findDismissed, isNot(contains(p.key)));
    });

    test('dismissals from before dismissal times existed are kept', () {
      final s = fresh();
      s.applyRemoteState({
        'tasks': <dynamic>[],
        'findDismissed': {'simplify:9': 'Old Co — Intern'},
        'updatedAt': 5,
      });
      expect(s.findDismissed, contains('simplify:9'));
    });
  });

  group('each setting keeps its own clock', () {
    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 3));

    test('an offline settings change survives a later edit elsewhere', () async {
      final a = fresh(), b = fresh()..applyRemoteState(copyOf(fresh()));
      // A, offline: changes Find's countries.
      a.setFindPrefs(FindPrefs()..countries = ['JP']);
      await tick();
      // B, later: only edits a task.
      b.addTask('Groceries', 'home');
      a.applyRemoteState(copyOf(b)); // A reconnects; B's copy is "newer"
      expect(a.findPrefs.countries, ['JP'], reason: 'B never touched Find settings');
      expect(a.tasks.where((t) => t.title == 'Groceries'), hasLength(1));
      expect(a.pendingMergePush, isTrue, reason: 'the cloud has the old countries');
      b.applyRemoteState(copyOf(a));
      expect(b.findPrefs.countries, ['JP'], reason: 'and it reaches B');
    });

    test('a later change to the same setting wins', () async {
      final a = fresh(), b = fresh();
      a.setFindPrefs(FindPrefs()..countries = ['JP']);
      await tick();
      b.setFindPrefs(FindPrefs()..countries = ['SG']);
      a.applyRemoteState(copyOf(b));
      expect(a.findPrefs.countries, ['SG']);
    });

    test('copies without clocks fall back to the whole-state clock', () {
      final a = fresh();
      a.applyRemoteState({
        'tasks': <dynamic>[],
        'wxPlace': 'Hong Kong', 'wxLat': 22.3, 'wxLon': 114.2,
        'updatedAt': DateTime.now().millisecondsSinceEpoch + 60000,
      });
      expect(a.weatherPlace, 'Hong Kong');
    });

    test('a signed-out device\'s defaults never beat the account\'s settings', () async {
      final account = fresh()..setFindPrefs(FindPrefs()..countries = ['JP']);
      final cloud = copyOf(account);
      await tick();
      final device = fresh();
      await device.wipeDevice(); // signed out: sample data, default settings
      device.addTask('Made while signed out', 'uni'); // an edit: newer clock
      device.applyRemoteState(cloud); // signs in
      expect(device.findPrefs.countries, ['JP']);
    });

    test('loading or merging is not an edit', () {
      final a = fresh()..setFindPrefs(FindPrefs()..countries = ['JP']);
      final stamped = a.settingsAt['find'];
      final b = fresh()..applyRemoteState(copyOf(a));
      expect(b.settingsAt['find'], stamped, reason: 'kept, not restamped');
      b.addTask('x', 'uni');
      expect(b.settingsAt['find'], stamped, reason: 'a task edit leaves Find\'s clock alone');
    });
  });

  test('only followed company boards get the follow bonus, not the lists', () {
    final prefs = FindPrefs();
    final taste = FindTaste.from(liked: const [], dismissed: const []);
    final board = findScore(posting('gh:acme:1', 'greenhouse'), prefs, taste);
    final simplify = findScore(posting('simplify:1', 'simplify'), prefs, taste);
    final speedy = findScore(posting('speedyapply:u', 'speedyapply'), prefs, taste);
    expect(board - simplify, 12);
    expect(speedy, simplify, reason: 'SpeedyApply is a list, like SimplifyJobs');
  });
}
