// Guards the sync rules that stop a stale device from winning:
//  - the housekeeping purge must not bump the sync clock (a device that merely
//    opened the app would otherwise look like the newest writer),
//  - a pull must not drop local tasks the cloud has never seen,
//  - but a task genuinely deleted on another device must stay deleted.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Map<String, dynamic> taskMap(int id, {int u = 0, bool done = false, int? doneAt}) => {
        'id': id,
        't': 'Task $id',
        'g': 'uni',
        'done': done,
        'doneAt': doneAt,
        'u': u,
      };

  test('purging week-old done tasks does not bump the sync clock', () {
    final s = CadenceStore();
    final ancient = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    s.applyState({
      'tasks': [
        taskMap(1, u: 100),
        taskMap(2, u: 100, done: true, doneAt: ancient),
      ],
      'updatedAt': 100,
    });

    s.purgeOldDone();

    expect(s.byId(2), isNull, reason: 'the stale done task should be removed');
    expect(s.updatedAt, 100,
        reason: 'a local purge must not make this device look like the newest '
            'writer, or it will push its old state over the cloud');
  });

  test('a local task the cloud has never seen survives a newer cloud pull', () {
    final s = CadenceStore();
    s.applyState({
      'tasks': [taskMap(1, u: 100)],
      'uid': 1, // so the next new task gets id 2, not a duplicate id 1
      'updatedAt': 100,
    });

    // We add a task locally; its per-task clock is "now".
    s.addTask('Fresh local task', 'uni');
    final fresh = s.tasks.firstWhere((t) => t.title == 'Fresh local task');
    expect(fresh.uAt, greaterThan(100));

    // The cloud meanwhile advanced, but its snapshot predates our new task.
    s.applyRemoteState({
      'tasks': [taskMap(1, u: 200)],
      'updatedAt': fresh.uAt - 1,
    });

    expect(s.tasks.where((t) => t.title == 'Fresh local task'), hasLength(1),
        reason: 'a task created after the cloud snapshot is unpushed local '
            'work, not a remote deletion');
  });

  test('a task deleted on another device stays deleted', () {
    final s = CadenceStore();
    s.applyState({
      'tasks': [taskMap(1, u: 100), taskMap(2, u: 100)],
      'updatedAt': 100,
    });
    expect(s.byId(2), isNotNull);

    // Another device deleted task 2 and pushed at t=500. Our copy of task 2 was
    // last touched at t=100, i.e. before that snapshot — so the cloud knew
    // about it and dropped it deliberately.
    s.applyRemoteState({
      'tasks': [taskMap(1, u: 100)],
      'updatedAt': 500,
    });

    expect(s.byId(2), isNull,
        reason: 'a remote deletion must not be resurrected by the merge');
  });

  test('keeping a local task does not rewind the id counter', () {
    final s = CadenceStore();
    s.applyState({
      'tasks': [taskMap(1, u: 100)],
      'uid': 1,
      'updatedAt': 100,
    });
    s.addTask('Local', 'uni');
    final localId = s.tasks.firstWhere((t) => t.title == 'Local').id;

    // Cloud snapshot from before our task, with a lower id counter.
    s.applyRemoteState({
      'tasks': [taskMap(1, u: 100)],
      'uid': 1,
      'updatedAt': s.tasks.firstWhere((t) => t.title == 'Local').uAt - 1,
    });

    s.addTask('Another', 'uni');
    final nextId = s.tasks.firstWhere((t) => t.title == 'Another').id;
    expect(nextId, isNot(localId),
        reason: 'a new task must not reuse the id of a task we kept');
  });
}
