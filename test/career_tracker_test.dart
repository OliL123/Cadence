// The career tracker's logic: the "what should I do today?" agenda, stats,
// CSV round-trips, and sync safety (incl. against blobs from older builds).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/tracker_csv.dart';
import 'package:cadence/tracker/tracker_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  var nextId = 0;
  int id() => ++nextId;

  group('agenda', () {
    // Wed 7 Oct 2026, 13:00 — the day before the career fair sign-up opens.
    final now = DateTime(2026, 10, 7, 13);
    final apps = starterApplications(id);
    final events = starterEvents(id);

    test('career fair sign-up opening within 48h is urgent', () {
      final a = CareerAgenda.build(apps, events, now: now);
      final titles = a.urgent.map((u) => '${u.title}|${u.detail}').toList();
      expect(titles, contains('Virtual Engineering Career Fair|sign-up opens'));
    });

    test('a deadline already handled is not urgent', () {
      final a = CareerAgenda.build(apps, events,
          now: DateTime(2026, 11, 5, 9)); // the day before Riot closes
      expect(a.urgent.where((u) => u.title == 'Riot application closes'), isEmpty);
    });

    test('this week lists upcoming and running events, not TBD ones', () {
      final a = CareerAgenda.build(apps, events, now: now);
      final names = a.thisWeek.map((u) => u.title).toList();
      expect(names, containsAll(['Virtual Engineering Career Fair',
          'MLH Global Hack Week: Hacktoberfest']));
      expect(names, isNot(contains('Epic Games recruiter coaching session')));
      expect(names, isNot(contains('Game Off 2026')), reason: 'that is in November');
    });

    test('follow-ups due today or earlier', () {
      final x = Application(id: id(), company: 'X', status: 'applied',
          nextAction: 'follow up', nextActionDate: '2026-10-07');
      final y = Application(id: id(), company: 'Y', status: 'applied',
          nextActionDate: '2026-10-12');
      final a = CareerAgenda.build([x, y], [], now: now);
      expect(a.followUps, [x]);
    });

    test('suggests ghosted after six weeks of silence', () {
      final old = Application(id: id(), company: 'Old', status: 'applied',
          dateApplied: '2026-08-25'); // 43 days before
      final recent = Application(id: id(), company: 'Recent', status: 'applied',
          dateApplied: '2026-08-28'); // 40 days before
      final a = CareerAgenda.build([old, recent], [], now: now);
      expect(a.ghostCandidates, [old]);
    });

    test('counts applications sent this week (Mon–Sun)', () {
      final a = CareerAgenda.build(apps, events, now: now);
      expect(a.appliedThisWeek, 1, reason: 'Riot was applied to on Tue 6 Oct');
    });
  });

  test('stats: response rate counts any answer, including rejection', () {
    final s = AppStats.of([
      Application(id: 1, company: 'a', status: 'to-apply'),
      Application(id: 2, company: 'b', status: 'applied'),
      Application(id: 3, company: 'c', status: 'interview'),
      Application(id: 4, company: 'd', status: 'rejected'),
      Application(id: 5, company: 'e', status: 'ghosted'),
    ]);
    expect(s.sent, 4);
    expect(s.responded, 2);
    expect(s.responseRate, .5);
  });

  test('CSV round-trips commas, quotes and line breaks', () {
    final a = Application(id: 7, company: 'Riot, Inc.', role: 'SWE "Intern"',
        status: 'applied', sponsorship: 'no-sponsorship',
        notes: 'Line one\nLine two, with a comma');
    final rows = parseCsv(applicationsToCsv([a]));
    expect(csvKind(rows), CsvKind.applications);
    final back = applicationsFromCsv(rows).single;
    expect(back.id, 7);
    expect(back.company, 'Riot, Inc.');
    expect(back.role, 'SWE "Intern"');
    expect(back.notes, 'Line one\nLine two, with a comma');
    expect(back.sponsorship, 'no-sponsorship');
  });

  test('CSV import: "TBD" dates and unknown enum values are tolerated', () {
    final rows = parseCsv('name,type,start,status\n'
        'Coaching,coaching,TBD,interested\n'
        'Mystery,party,2026-12-01,going\n');
    expect(csvKind(rows), CsvKind.events);
    final ev = eventsFromCsv(rows);
    expect(ev[0].start, isNull);
    expect(ev[1].type, 'other');
    expect(ev[1].status, 'interested');
  });

  test('import updates rows by id and adds the rest', () {
    final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    s.loadCareerStarter();
    final riot = s.applications.firstWhere((a) => a.company == 'Riot Games');
    final edited = Application.fromJson(riot.toJson())..status = 'oa';
    final r = s.importApplications([edited, Application(id: 0, company: 'Valve')]);
    expect((r.added, r.updated), (1, 1));
    expect(s.applications.firstWhere((a) => a.company == 'Riot Games').status, 'oa');
    expect(s.applications.length, 6);
  });

  group('sync', () {
    test('a blob from an older build does not wipe career data or score', () {
      final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
      s.loadCareerStarter();
      s.score = 9;
      // An older client syncs a newer copy that knows nothing of these fields.
      s.applyRemoteState({'tasks': <dynamic>[], 'updatedAt': DateTime.now().millisecondsSinceEpoch + 5000});
      expect(s.applications, hasLength(5));
      expect(s.trackEvents, hasLength(7));
      expect(s.score, 9);
    });

    test('a newer local edit to an application survives a cloud pull', () {
      final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
      s.loadCareerStarter();
      final cloud = s.exportState(); // snapshot before the edit
      final amazon = s.applications.firstWhere((a) => a.company == 'Amazon');
      s.setAppStatus(amazon, 'applied');
      s.applyRemoteState({...cloud, 'updatedAt': amazon.uAt + 1});
      expect(s.applications.firstWhere((a) => a.company == 'Amazon').status, 'applied');
    });
  });
}
