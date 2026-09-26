// Subtasks can be reordered by dragging their handle, the new order is kept by
// the store (and stamped for sync), and an open title edit follows its subtask
// rather than its old row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/models.dart';
import 'package:cadence/store.dart';
import 'package:cadence/widgets/subtasks.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  Task taskWith(List<String> subs) => Task(
      id: 1, title: 'T', group: 'uni', sub: [for (final s in subs) SubTask(s)]);

  List<String> order(Task t) => t.sub.map((s) => s.title).toList();

  test('reorderSub moves a subtask and stamps the task for sync', () {
    final t = taskWith(['A', 'B', 'C', 'D']);
    store.tasks = [t];
    final before = t.uAt;
    store.reorderSub(t, 0, 2); // A to third place
    expect(order(t), ['B', 'C', 'A', 'D']);
    expect(t.uAt, greaterThan(before),
        reason: 'the per-task clock must advance so the order syncs');
    store.reorderSub(t, 3, 0); // D to the top
    expect(order(t), ['D', 'B', 'C', 'A']);
    store.reorderSub(t, 9, 0); // out of range: ignored
    expect(order(t), ['D', 'B', 'C', 'A']);
  });

  Future<void> pump(WidgetTester tester, Task t) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: store,
              builder: (_, __) => SubtaskSection(task: t, color: Colors.red),
            ),
          ),
        ),
      ));

  testWidgets('dragging a handle reorders the subtasks', (tester) async {
    final t = taskWith(['A', 'B', 'C']);
    store.tasks = [t];
    await pump(tester, t);

    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
    final g = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_indicator).first));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(order(t).first, isNot('A'), reason: 'A was dragged down');
    expect(order(t).last, 'A');
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('a single subtask shows no handle', (tester) async {
    final t = taskWith(['Only']);
    store.tasks = [t];
    await pump(tester, t);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
  });

  testWidgets('an open edit stays on its subtask after a reorder', (tester) async {
    final t = taskWith(['A', 'B', 'C']);
    store.tasks = [t];
    await pump(tester, t);

    await tester.tap(find.text('C'));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(2)); // editor + add field

    // C moves to the top while its editor is open (e.g. a sync landed).
    store.reorderSub(t, 2, 0);
    await tester.pump();

    final editor = tester.widget<TextField>(find.byType(TextField).first);
    expect(editor.controller!.text, 'C',
        reason: 'the editor follows C, not whatever is now in its old row');
  });
}
