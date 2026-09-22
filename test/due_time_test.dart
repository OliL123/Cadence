// Due dates carry a time of day, but the countdown helpers used to compare
// whole days only — so a task due at 18:00 stayed "today" all evening and
// wasn't flagged overdue until the next calendar day.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/models.dart';
import 'package:cadence/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Task task({String? due, String? time}) =>
      Task(id: 1, title: 'T', group: 'uni', dueISO: due, dueTime: time);

  final s = CadenceStore();

  test('a time earlier today is overdue', () {
    final past = DateTime.now().subtract(const Duration(hours: 2));
    final t = task(due: iso(past), time: hm(past));
    expect(s.isOverdue(t), isTrue);
    expect(s.dueLabel(t), startsWith('overdue'));
  });

  test('a time later today is not overdue', () {
    final soonish = DateTime.now().add(const Duration(hours: 2));
    // Skip if "2 hours from now" has rolled past midnight into tomorrow.
    if (soonish.day != DateTime.now().day) return;
    final t = task(due: iso(soonish), time: hm(soonish));
    expect(s.isOverdue(t), isFalse);
    expect(s.dueLabel(t), startsWith('today'));
  });

  test('a date with no time is not overdue until the day is out', () {
    final today = DateTime.now();
    final t = task(due: iso(today));
    expect(s.isOverdue(t), isFalse,
        reason: 'a date-only task has all day to be finished');
    expect(s.dueAt(t)!.hour, 23);
  });

  test('yesterday is overdue with or without a time', () {
    final y = DateTime.now().subtract(const Duration(days: 1));
    expect(s.isOverdue(task(due: iso(y))), isTrue);
    expect(s.isOverdue(task(due: iso(y), time: '09:00')), isTrue);
  });

  test('soon() covers today through two days out, by calendar day', () {
    final n = DateTime.now();
    DateTime day(int k) => DateTime(n.year, n.month, n.day + k);
    expect(s.soon(task(due: iso(day(0)))), isTrue);
    expect(s.soon(task(due: iso(day(1)))), isTrue);
    expect(s.soon(task(due: iso(day(3)))), isFalse);
    expect(s.soon(task(due: iso(day(-1)))), isTrue, reason: 'overdue is urgent too');
  });

  test('a date-only task two days out is on the urgent list', () {
    // Regression: a rolling 48h window measured date-only tasks to 23:59, so
    // this fell off the list and only tasks with a time set showed up.
    final n = DateTime.now();
    final inTwo = DateTime(n.year, n.month, n.day + 2);
    expect(s.soon(task(due: iso(inTwo))), isTrue);
    expect(s.soon(task(due: iso(inTwo), time: '23:00')), isTrue,
        reason: 'with or without a time, it is the same day');
  });

  test('done and daily tasks are never overdue', () {
    final y = DateTime.now().subtract(const Duration(days: 2));
    final done = task(due: iso(y))..done = true;
    final daily = task(due: iso(y))..daily = true;
    expect(s.isOverdue(done), isFalse);
    expect(s.isOverdue(daily), isFalse);
  });
}
