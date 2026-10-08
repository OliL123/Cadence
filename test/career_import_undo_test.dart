// A big CSV import needs to be reversible, and a board of hundreds of roles
// needs to read as companies with a one-tap "applied".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/career_page.dart';
import 'package:cadence/tracker/tracker_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  List<Application> sheet(int n) => [
        for (var i = 0; i < n; i++)
          Application(id: 0, company: 'Co ${i % 4}', role: 'Role $i'),
      ];

  group('undo an import', () {
    late CadenceStore s;
    setUp(() async {
      s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
      s.saveApplication(Application(id: 0, company: 'Mine', role: 'by hand'));
      // a person can't add by hand and import in the same millisecond
      await Future<void>.delayed(const Duration(milliseconds: 2));
    });

    test('the import UNDO removes exactly the rows it added', () {
      final r = s.importApplications(sheet(40));
      expect(s.applications, hasLength(41));
      s.removeCareerItems(r.ids, const []);
      expect(s.applications.map((a) => a.company), ['Mine']);
    });

    test('an earlier import is listed and can be taken back, then restored', () {
      s.importApplications(sheet(40));
      final batches = s.importBatches();
      expect(batches.first.apps, 40);
      final gone = s.removeImportBatch(batches.first.at);
      expect(gone.apps, hasLength(40));
      expect(s.applications.map((a) => a.company), ['Mine']);
      s.restoreCareer(gone.apps, gone.events);
      expect(s.applications, hasLength(41));
      expect(s.deleted.keys.where((k) => k.startsWith('a:')), isEmpty,
          reason: 'restored rows must not stay marked deleted');
    });

    test('rows edited since the import are kept', () async {
      s.importApplications(sheet(10));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final edited = s.applications.firstWhere((a) => a.role == 'Role 3');
      s.setAppStatus(edited, 'applied');
      s.removeImportBatch(s.importBatches().first.at);
      expect(s.applications.map((a) => a.role), containsAll(['by hand', 'Role 3']));
      expect(s.applications, hasLength(2));
    });

    test('a removed import stays removed through a sync from the old copy', () {
      s.importApplications(sheet(10));
      final before = s.exportState();
      s.removeImportBatch(s.importBatches().first.at);
      s.applyRemoteState(before);
      expect(s.applications, hasLength(1));
    });

    test('marking applied can be undone exactly', () {
      final a = s.applications.first;
      s.setAppStatus(a, 'applied');
      expect(s.applications.first.dateApplied, isNotNull);
      s.revertAppStatus(a, 'to-apply', null);
      expect((s.applications.first.status, s.applications.first.dateApplied), ('to-apply', null));
    });
  });

  testWidgets('a company with many roles is one card, opened to tick one off', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.applications = [];
    store.trackEvents = [];
    store.goals = [];
    store.importApplications([
      for (var i = 0; i < 6; i++) Application(id: 0, company: 'Riot', role: 'Role $i'),
      Application(id: 0, company: 'Valve', role: 'Solo role'),
    ]);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CareerPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applications 7'));
    await tester.pumpAndSettle();

    expect(find.text('Riot'), findsOneWidget, reason: 'six roles, one card');
    expect(find.text('6 ROLES'), findsOneWidget);
    expect(find.text('Role 5'), findsNothing);

    await tester.tap(find.text('Riot'));
    await tester.pumpAndSettle();
    expect(find.text('Role 5'), findsOneWidget);

    // Tick "Role 2" applied straight from the open card.
    final row = find.ancestor(of: find.text('Role 2'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('Mark applied')));
    await tester.pumpAndSettle();
    expect(store.applications.firstWhere((a) => a.role == 'Role 2').status, 'applied');
    expect(find.text('5 ROLES'), findsOneWidget);
    expect(find.text('UNDO'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(store.applications.firstWhere((a) => a.role == 'Role 2').status, 'to-apply');
  });
}
