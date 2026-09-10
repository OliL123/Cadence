// Verifies the per-task sync merge: a stale device's blob (newer top-level
// clock, older per-task clock) must not revert a task we just made a daily.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Map<String, dynamic> taskMap(int id, {bool daily = false, int u = 0}) =>
      {'id': id, 't': 'Task $id', 'g': 'uni', 'daily': daily, 'u': u};

  test('a task made daily survives a stale-device sync (per-task LWW)', () {
    final s = CadenceStore();
    // Seed one normal task, synced at t=100.
    s.applyState({
      'tasks': [taskMap(1, daily: false, u: 100)],
      'updatedAt': 100,
    });
    expect(s.byId(1)!.daily, isFalse);

    // Make it a daily locally (stamps its per-task clock to "now").
    s.setDaily(s.byId(1)!, true);
    expect(s.byId(1)!.daily, isTrue);
    final localUAt = s.byId(1)!.uAt;
    expect(localUAt, greaterThan(100));

    // A stale device pushes its whole state: the task is still non-daily with
    // the OLD per-task clock, but the blob's top-level clock is far in the
    // future (that device made some unrelated edit last).
    s.applyRemoteState({
      'tasks': [taskMap(1, daily: false, u: 100)],
      'updatedAt': localUAt + 1000000,
    });

    // The per-task merge must keep our newer "made daily" edit.
    expect(s.byId(1)!.daily, isTrue,
        reason: 'stale blob should not revert the daily flag');
    expect(s.pendingMergePush, isTrue,
        reason: 'the corrected merge should be pushed back to the cloud');
  });

  test('a genuinely newer remote edit still wins', () {
    final s = CadenceStore();
    s.applyState({
      'tasks': [taskMap(1, daily: true, u: 100)],
      'updatedAt': 100,
    });
    expect(s.byId(1)!.daily, isTrue);

    // Remote edited THIS task more recently (higher per-task clock) → wins.
    s.applyRemoteState({
      'tasks': [taskMap(1, daily: false, u: 500)],
      'updatedAt': 500,
    });
    expect(s.byId(1)!.daily, isFalse,
        reason: 'a newer per-task edit from another device should apply');
  });
}
