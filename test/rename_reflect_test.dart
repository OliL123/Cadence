// Renaming a task must reflect everywhere it appears: the mahjong wall, the
// due-soon list, and it must never merge two tasks that happen to share a name
// (tasks are identified by id, not title).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('rename shows on the mahjong wall (same live object)', () {
    final s = CadenceStore();
    s.applyState({'tasks': <dynamic>[], 'uid': 0, 'updatedAt': 1});
    s.addTask('Old name', 'uni');
    final t = s.tasks.first;
    s.toggleStar(t); // puts it on the wall with a tile
    expect(s.wallTasks().map((x) => x.title), contains('Old name'));

    s.setTitle(t, 'New name');
    expect(s.wallTasks().map((x) => x.title), contains('New name'));
    expect(s.wallTasks().map((x) => x.title), isNot(contains('Old name')));
  });

  test('two tasks with the same name stay distinct', () {
    final s = CadenceStore();
    s.applyState({'tasks': <dynamic>[], 'uid': 0, 'updatedAt': 1});
    s.addTask('Buy milk', 'uni');
    s.addTask('Buy milk', 'home');
    expect(s.tasks.length, 2);
    final ids = s.tasks.map((t) => t.id).toSet();
    expect(ids.length, 2, reason: 'each task has its own id');

    // Completing one leaves the other untouched.
    s.toggleDone(s.tasks.first);
    final done = s.tasks.where((t) => t.done).toList();
    final open = s.tasks.where((t) => !t.done).toList();
    expect(done.length, 1);
    expect(open.length, 1);
    expect(done.first.id, isNot(open.first.id));

    // Both can sit on the wall as separate tiles.
    for (final t in s.tasks.where((t) => !t.done)) {
      s.toggleStar(t);
    }
    expect(s.wallTasks().length, 1); // only the open one is eligible
  });
}
