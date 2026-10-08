// The Applications tab with a big list: search narrows it, and the default
// List view spreads cards across the width instead of one narrow column.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/career_page.dart';
import 'package:cadence/tracker/tracker_models.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  Future<void> open(WidgetTester tester, {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.applications = [];
    store.trackEvents = [];
    store.goals = [];
    store.importApplications([
      Application(id: 0, company: 'Riot', role: 'Unity Gameplay Intern', location: 'LA'),
      Application(id: 0, company: 'Riot', role: 'Backend Intern'),
      Application(id: 0, company: 'Valve', role: 'Unity Tools Intern'),
      Application(id: 0, company: 'Bungie', role: 'QA Intern', location: 'Seattle'),
      Application(id: 0, company: 'Lantern', role: 'SWE Intern', status: 'rejected'),
    ]);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CareerPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applications 5'));
    await tester.pumpAndSettle();
  }

  testWidgets('cards flow across the width, side by side', (tester) async {
    await open(tester);
    final valve = tester.getTopLeft(find.text('Valve'));
    final bungie = tester.getTopLeft(find.text('Bungie'));
    expect(valve.dy, bungie.dy, reason: 'same row');
    expect(valve.dx, isNot(bungie.dx));
  });

  testWidgets('closed outcomes start folded and open on tap', (tester) async {
    await open(tester);
    expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('Lantern'), findsNothing);
    await tester.tap(find.text('REJECTED'));
    await tester.pumpAndSettle();
    expect(find.text('Lantern'), findsOneWidget);
  });

  testWidgets('search matches every word across company, role and place', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'unity');
    await tester.pumpAndSettle();
    expect(find.text('Valve'), findsOneWidget);
    expect(find.text('Riot'), findsOneWidget);
    expect(find.text('Bungie'), findsNothing);

    await tester.enterText(find.byType(TextField), 'riot unity');
    await tester.pumpAndSettle();
    expect(find.text('Valve'), findsNothing);
    expect(find.text('Riot'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'seattle');
    await tester.pumpAndSettle();
    expect(find.text('Bungie'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'lantern');
    await tester.pumpAndSettle();
    expect(find.text('Lantern'), findsOneWidget, reason: 'a search opens folded sections');

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Bungie'), findsOneWidget);
  });

  testWidgets('cards in a row are the same height', (tester) async {
    await open(tester);
    // Valve (one role) and Bungie (one role, shorter text) sit side by side.
    Size cardOf(String company) => tester.getSize(find
        .ancestor(of: find.text(company), matching: find.byType(Ink))
        .first);
    expect(cardOf('Valve').height, cardOf('Bungie').height);
  });

  testWidgets('pressing and marked-important companies lead, in big cards', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.applications = [];
    store.trackEvents = [];
    store.careerPins = [];
    final soon = DateTime.now().add(const Duration(days: 2));
    final iso = '${soon.year}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
    store.importApplications([
      for (var i = 0; i < 10; i++) Application(id: 0, company: 'Filler $i', role: 'Intern'),
      Application(id: 0, company: 'Closing Soon Co', role: 'Intern', deadline: iso),
      Application(id: 0, company: 'Dream Studio', role: 'Gameplay Intern'),
    ]);
    store.togglePin('dream studio');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CareerPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applications 12'));
    await tester.pumpAndSettle();

    final dream = tester.getTopLeft(find.text('Dream Studio'));
    final closing = tester.getTopLeft(find.text('Closing Soon Co'));
    final filler = tester.getTopLeft(find.text('Filler 0'));
    expect(dream.dy, lessThan(closing.dy), reason: 'marked important comes first');
    expect(closing.dy, lessThan(tester.getTopLeft(find.text('Filler 9')).dy));
    expect(dream.dx, lessThan(filler.dx), reason: 'big cards on the left, small beside');
    expect(find.byTooltip('Unmark important'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('marked-important companies sync, and an older copy without them keeps ours', () {
    final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    s.togglePin('Riot Games');
    expect(s.isPinned('  riot games '), isTrue);
    final old = s.exportState()..remove('careerPins');
    s.applyRemoteState(old);
    expect(s.isPinned('Riot Games'), isTrue);
    final other = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    other.applyRemoteState(s.exportState());
    expect(other.isPinned('Riot Games'), isTrue);
  });

  testWidgets('Board still shows the status columns', (tester) async {
    await open(tester);
    await tester.tap(find.text('Board'));
    await tester.pumpAndSettle();
    expect(find.text('TO APPLY'), findsOneWidget);
    expect(find.text('INTERVIEW'), findsOneWidget, reason: 'empty columns are shown on the board');
  });

  testWidgets('on a phone the list is one card wide and nothing overflows', (tester) async {
    await open(tester, width: 390);
    final valve = tester.getTopLeft(find.text('Valve'));
    final bungie = tester.getTopLeft(find.text('Bungie'));
    expect(valve.dy, isNot(bungie.dy));
    expect(tester.takeException(), isNull);
  });
}
