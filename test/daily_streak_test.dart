// A daily's streak is judged by the gap in calendar days between its stored
// doneDate and today. Two things used to reset a live streak:
//  - "yesterday" was computed as now minus 24 hours, which lands back on today
//    when a daylight-saving change makes the local day 25 hours long;
//  - a doneDate from a device in a timezone ahead reads as neither today nor
//    yesterday, so the next tick started from zero.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/models.dart';
import 'package:cadence/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  String dayOffset(int days) {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day + days);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  CadenceStore storeWith(Task t) {
    final s = CadenceStore();
    s.applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    s.tasks.add(t);
    return s;
  }

  Task daily({String? doneDate, int streak = 0}) => Task(
      id: 1, title: 'Stretch', group: 'health', daily: true)
    ..doneDate = doneDate
    ..streak = streak;

  test('a run ticked yesterday continues instead of restarting', () {
    final t = daily(doneDate: dayOffset(-1), streak: 5);
    final s = storeWith(t);
    expect(s.dailyStreak(t), 5, reason: 'the run is still alive');
    expect(s.dailyDoneToday(t), isFalse);

    s.toggleDailyDone(t);
    expect(t.streak, 6);
    expect(s.dailyDoneToday(t), isTrue);
  });

  test('a doneDate from a device a timezone ahead does not reset the run', () {
    // Another device ticked it where it is already tomorrow.
    final t = daily(doneDate: dayOffset(1), streak: 7);
    final s = storeWith(t);
    expect(s.dailyStreak(t), 7, reason: 'still done, not a missed day');
    expect(s.dailyDoneToday(t), isTrue,
        reason: 'a date ahead of us counts as done, not pending');

    // Tapping it must undo, not start a fresh run at 1.
    s.toggleDailyDone(t);
    expect(t.streak, 6);
  });

  test('a genuinely missed day resets the run to 1', () {
    final t = daily(doneDate: dayOffset(-3), streak: 9);
    final s = storeWith(t);
    expect(s.dailyStreak(t), 0, reason: 'the run is broken');

    s.toggleDailyDone(t);
    expect(t.streak, 1);
    expect(s.dailyDoneToday(t), isTrue);
  });

  test('ticking then un-ticking returns to exactly where it was', () {
    final t = daily(doneDate: dayOffset(-1), streak: 4);
    final s = storeWith(t);
    s.toggleDailyDone(t);
    expect(t.streak, 5);
    s.toggleDailyDone(t);
    expect(t.streak, 4);
    expect(s.dailyStreak(t), 4, reason: 'the run is intact and still alive');
    expect(s.dailyDoneToday(t), isFalse);
  });

  test('a first-ever tick starts at 1 and un-ticks back to nothing', () {
    final t = daily();
    final s = storeWith(t);
    expect(s.dailyStreak(t), 0);
    s.toggleDailyDone(t);
    expect(t.streak, 1);
    s.toggleDailyDone(t);
    expect(t.streak, 0);
    expect(t.doneDate, isNull);
  });
}
