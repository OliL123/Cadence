// Drives the Career page: tabs, the add form, and moving a card along the
// pipeline.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/career_page.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CareerPage())));
    await tester.pumpAndSettle();
  }

  testWidgets('empty state offers the starting list', (tester) async {
    store.applications = [];
    store.trackEvents = [];
    await pump(tester);
    expect(find.text('Load my starting list'), findsOneWidget);
    await tester.tap(find.text('Load my starting list'));
    await tester.pumpAndSettle();
    expect(store.applications, hasLength(5));
    expect(store.trackEvents, hasLength(7));
    // The overview: schedule on the left, goals on the right.
    expect(find.text('MY GOALS'), findsOneWidget);
    expect(find.text('PIPELINE'), findsOneWidget);
    await tester.dragUntilVisible(find.text('DATE TBD'), find.byType(ListView).first,
        const Offset(0, -300));
    expect(find.text('Epic Games recruiter coaching session'), findsOneWidget);
  });

  testWidgets('a goal can be added from the overview', (tester) async {
    store.applications = [];
    store.trackEvents = [];
    store.goals = [];
    store.loadCareerStarter();
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Goal *'), 'Apply to 40');
    await tester.enterText(find.widgetWithText(TextField, 'Target *'), '40');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.goals.single.target, 40);
    expect(find.text('Apply to 40'), findsOneWidget);
  });

  testWidgets('applications board and events list render', (tester) async {
    store.applications = [];
    store.trackEvents = [];
    store.loadCareerStarter();
    await pump(tester);

    await tester.tap(find.text('Applications 5'));
    await tester.pumpAndSettle();
    expect(find.text('TO APPLY'), findsOneWidget);
    expect(find.text('Microsoft'), findsOneWidget);
    expect(find.text('NO SPONSORSHIP'), findsOneWidget, reason: 'Riot is flagged');

    await tester.tap(find.text('Events 7'));
    await tester.pumpAndSettle();
    // The list builds lazily; scroll down to the undated group.
    await tester.dragUntilVisible(find.text('DATE TBD'), find.byType(ListView).first,
        const Offset(0, -300));
    expect(find.text('DATE TBD'), findsOneWidget, reason: 'the Epic coaching session');
  });

  testWidgets('add an application through the form, then move it', (tester) async {
    store.applications = [];
    store.trackEvents = [];
    store.loadCareerStarter();
    await pump(tester);
    await tester.tap(find.text('Applications 5'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Company *'), 'Valve');
    await tester.enterText(find.widgetWithText(TextField, 'Role'), 'Game Dev Intern');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final valve = store.applications.singleWhere((a) => a.company == 'Valve');
    expect(valve.status, 'to-apply');
    expect(find.text('Valve'), findsOneWidget);

    store.setAppStatus(valve, 'applied');
    await tester.pumpAndSettle();
    expect(valve.dateApplied, isNotNull, reason: 'applying stamps today');
  });

  testWidgets('saving without a company shows an error', (tester) async {
    store.applications = [];
    store.trackEvents = [];
    store.loadCareerStarter();
    await pump(tester);
    await tester.tap(find.text('Applications 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Company is required'), findsOneWidget);
    expect(store.applications, hasLength(5));
  });
}
