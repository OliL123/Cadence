// Importing a sheet twice (or one that overlaps what's in the app) used to add
// every row again. Import now skips copies, and "Remove duplicates" collapses
// the ones already made without losing anything typed into either copy.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/tracker_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  CadenceStore fresh() => CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
  List<Application> sheet() => [
        Application(id: 0, company: 'Riot', role: 'SWE Intern', term: 'Summer 2027'),
        Application(id: 0, company: 'Valve', role: 'Gameplay Intern'),
      ];

  test('importing the same sheet twice adds nothing the second time', () {
    final s = fresh();
    expect(s.importApplications(sheet()).added, 2);
    final again = s.importApplications(sheet());
    expect((again.added, again.skipped), (0, 2));
    expect(s.applications.length, 2);
  });

  test('copies inside one file, and case/spacing differences, are skipped', () {
    final s = fresh();
    final r = s.importApplications([
      ...sheet(),
      Application(id: 0, company: ' riot ', role: 'swe  intern', term: 'summer 2027'),
    ]);
    expect((r.added, r.skipped), (2, 1));
  });

  test('same company, different role or term, is not a copy', () {
    final s = fresh()..importApplications(sheet());
    final r = s.importApplications([
      Application(id: 0, company: 'Riot', role: 'SWE Intern', term: 'Summer 2028'),
      Application(id: 0, company: 'Riot', role: 'Art Intern', term: 'Summer 2027'),
    ]);
    expect(r.added, 2);
  });

  test('events match on name and start day', () {
    final s = fresh();
    TrackEvent ev(String start) => TrackEvent(id: 0, name: 'Career Fair', type: 'career-fair', start: start);
    s.importEvents([ev('2026-10-20')]);
    final r = s.importEvents([ev('2026-10-20 10:00'), ev('2026-11-03')]);
    expect((r.added, r.skipped), (1, 1));
  });

  test('remove duplicates keeps the furthest-along copy and fills its blanks', () {
    final s = fresh();
    s.applications = [
      Application(id: 1, company: 'Riot', role: 'SWE Intern', notes: 'ask Sam'),
      Application(id: 2, company: 'Riot', role: 'SWE Intern', status: 'applied'),
      Application(id: 3, company: 'Riot', role: 'SWE Intern', link: 'riotgames.com/jobs'),
      Application(id: 4, company: 'Valve', role: 'Gameplay Intern'),
    ];
    expect(s.countDuplicates().apps, 2);
    final r = s.removeDuplicates();
    expect(r.apps, 2);
    expect(s.applications.map((a) => a.id), [2, 4], reason: 'order kept, applied copy wins');
    final kept = s.applications.first;
    expect(kept.status, 'applied');
    expect(kept.notes, 'ask Sam');
    expect(kept.link, isNotNull);
    expect(s.countDuplicates().apps, 0);
  });

  test('a sync from a copy that still has the duplicates does not bring them back', () {
    final s = fresh();
    s.importApplications(sheet());
    // simulate the double import, as the cloud saw it
    var nextId = 900;
    s.applications = [
      ...s.applications,
      for (final a in sheet()) a..id = ++nextId,
    ];
    expect(s.applications.length, 4);
    final withDupes = jsonDecode(jsonEncode(s.exportState())) as Map<String, dynamic>;
    s.removeDuplicates();
    s.applyRemoteState(withDupes);
    expect(s.applications.length, 2);
  });
}
