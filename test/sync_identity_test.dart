// A sync (or a reload on resume) can swap the store's Task objects for fresh
// copies. UNDO buttons, the date-then-time pickers and the subtask editor all
// hold on to the Task they started with, and used to edit that stray copy —
// so the change silently vanished. These replay those flows across a sync.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/tracker_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  CadenceStore fresh() {
    final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    s.addTask('Essay', s.groups.first.key);
    return s;
  }

  /// The same state coming back from the cloud: our own push echoing.
  void echo(CadenceStore s) => s.applyRemoteState(s.exportState());

  /// Another device edited task [id] after us (newer clock, new title).
  void newerFromElsewhere(CadenceStore s, int id, String title) {
    final st = s.exportState();
    for (final j in st['tasks'] as List) {
      if (j['id'] == id) {
        j['t'] = title;
        j['u'] = (j['u'] as int) + 5000;
      }
    }
    s.applyRemoteState(st);
  }

  test('our own echo keeps the same task objects', () {
    final s = fresh();
    final t = s.tasks.first;
    s.setTitle(t, 'Essay draft');
    echo(s);
    expect(identical(s.tasks.first, t), isTrue);
  });

  test('UNDO after a sync reopens the task', () {
    final s = fresh();
    final t = s.tasks.first;
    s.toggleDone(t);
    echo(s);
    s.toggleDone(t); // UNDO
    expect(s.byId(t.id)!.done, isFalse);
  });

  test('picking a time after the date has synced keeps the time', () {
    final s = fresh();
    final t = s.tasks.first;
    s.setDue(t, DateTime(2026, 10, 20));
    echo(s); // the push lands while the time dialog is open
    s.setDueTime(t, '18:30');
    expect(s.byId(t.id)!.dueTime, '18:30');
  });

  test('an edit lands even when a newer copy replaced the object', () {
    final s = fresh();
    final t = s.tasks.first;
    newerFromElsewhere(s, t.id, 'Essay (from phone)');
    expect(identical(s.tasks.first, t), isFalse, reason: 'newer remote wins');
    s.setDueTime(t, '09:00');
    s.moveTask(t, s.groups.last.key);
    final live = s.byId(t.id)!;
    expect(live.dueTime, '09:00');
    expect(live.group, s.groups.last.key);
    expect(live.title, 'Essay (from phone)', reason: 'the other edit survives too');
  });

  test('subtask edits land after the task object was replaced', () {
    final s = fresh();
    final t = s.tasks.first;
    s.addSub(t, 'outline');
    s.addSub(t, 'draft');
    final draft = t.sub[1];
    newerFromElsewhere(s, t.id, 'Essay v2');
    s.renameSub(t, draft, 'first draft');
    s.toggleSub(t, draft);
    final live = s.byId(t.id)!;
    expect(live.sub[1].title, 'first draft');
    expect(live.sub[1].done, isTrue);
    s.deleteSub(t, live.sub[0]);
    expect(s.byId(t.id)!.sub.map((x) => x.title), ['first draft']);
  });

  test('UNDO of a delete does not duplicate a task a sync brought back', () {
    final s = fresh();
    final t = s.tasks.first;
    s.insertTask(t, 0); // already there
    expect(s.tasks.where((x) => x.id == t.id).length, 1);
  });

  test('expanding a task is not an edit, so it cannot beat one from elsewhere', () {
    final s = fresh();
    final t = s.tasks.first;
    final before = t.uAt;
    s.toggleOpen(t);
    expect(s.byId(t.id)!.open, isTrue);
    expect(s.byId(t.id)!.uAt, before);
  });

  test('a malformed date is ignored, not a crash', () {
    expect(CadenceStore.parseISO('2026-1O-05'), isNull);
    expect(CadenceStore.parseISO('2026-10-05'), DateTime(2026, 10, 5));
  });

  test('a passed to-apply deadline stays urgent for a week', () {
    final now = DateTime(2026, 10, 7, 13);
    Application app(String dl, [String status = 'to-apply']) =>
        Application(id: dl.hashCode, company: 'Co $dl', status: status, deadline: dl);
    final a = CareerAgenda.build(
        [app('2026-10-05'), app('2026-09-20'), app('2026-10-04', 'applied')], [],
        now: now);
    expect(a.urgent.map((u) => u.app!.company), ['Co 2026-10-05'],
        reason: 'last week stays; older or already applied do not');
  });
}
