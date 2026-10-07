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

    test('the compact list has one sign-up item per event; the full list keeps both', () {
      List<String> fair(List<AgendaItem> items) => items
          .where((u) => u.title == 'Virtual Engineering Career Fair')
          .map((u) => u.detail)
          .toList();
      // Opens Thu 12:00, closes Fri 12:00: both inside 48h.
      final a = CareerAgenda.build(apps, events, now: now);
      expect(fair(a.urgent), ['sign-up opens', 'sign-up closes']);
      expect(fair(a.urgentCompact), ['sign-up opens']);
      // Window open now: only "closes" is left.
      final b = CareerAgenda.build(apps, events, now: DateTime(2026, 10, 8, 15));
      expect(fair(b.urgentCompact), ['sign-up closes']);
    });

    test('the compact list drops sign-ups once signed up', () {
      final evs = starterEvents(id);
      evs.firstWhere((e) => e.name == 'Virtual Engineering Career Fair').status = 'signed-up';
      final a = CareerAgenda.build(apps, evs, now: now);
      expect(a.urgentCompact.where((u) => u.title == 'Virtual Engineering Career Fair'),
          isEmpty);
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

  group('schedule', () {
    final now = DateTime(2026, 10, 7, 13);

    test('lists everything coming up, months out, soonest first', () {
      final s = CareerSchedule.build(starterApplications(id), starterEvents(id), now: now);
      final names = s.upcoming.map((u) => '${u.title}|${u.detail}').toList();
      expect(names.first, 'Virtual Engineering Career Fair|sign-up opens');
      expect(names, contains('HackRPI 2026|hackathon'));
      expect(names, contains('SpartaHack 12|hackathon'), reason: 'February is still shown');
      expect(names, contains('Riot application closes|deadline'));
      expect(s.upcoming.map((u) => u.when).toList(),
          orderedEquals([...s.upcoming.map((u) => u.when)]..sort()));
      expect(s.tbd.map((e) => e.name), contains('Epic Games recruiter coaching session'));
      expect(s.next!.detail, 'sign-up opens');
    });

    test('running events are "now", past ones are gone', () {
      final s = CareerSchedule.build([], starterEvents(id), now: DateTime(2026, 10, 12, 9));
      expect(s.running.map((u) => u.title), contains('MLH Global Hack Week: Hacktoberfest'));
      expect(s.upcoming.map((u) => u.title), isNot(contains('Virtual Engineering Career Fair')));
    });

    test('one sign-up line per event, none once signed up', () {
      final evs = starterEvents(id);
      final fair = evs.firstWhere((e) => e.name == 'Virtual Engineering Career Fair');
      List<String> lines() => CareerSchedule.build([], evs, now: now)
          .upcoming
          .where((u) => u.title == fair.name && u.detail.startsWith('sign-up'))
          .map((u) => u.detail)
          .toList();
      expect(lines(), ['sign-up opens']);
      fair.status = 'signed-up';
      expect(lines(), isEmpty);
    });
  });

  group('goals', () {
    test('counted goals count from their start date', () {
      final apps = [
        Application(id: 1, company: 'a', status: 'applied', dateApplied: '2026-09-01'),
        Application(id: 2, company: 'b', status: 'applied', dateApplied: '2026-10-02'),
        Application(id: 3, company: 'c', status: 'interview', dateApplied: '2026-10-03'),
        Application(id: 4, company: 'd', status: 'to-apply'),
      ];
      final evs = [
        TrackEvent(id: 5, name: 'jam', type: 'game-jam', start: '2026-10-05', status: 'attended'),
        TrackEvent(id: 6, name: 'fair', type: 'career-fair', start: '2026-10-06', status: 'attended'),
        TrackEvent(id: 7, name: 'hack', type: 'hackathon', start: '2026-11-07', status: 'signed-up'),
      ];
      int p(String metric, {String? since}) =>
          Goal(id: 9, title: 'g', metric: metric, since: since).progress(apps, evs);
      expect(p('applied'), 3);
      expect(p('applied', since: '2026-10-01'), 2);
      expect(p('interviews'), 1);
      expect(p('attended'), 2);
      expect(p('hackathons'), 1);
      expect((Goal(id: 9, title: 'g', count: 4)).progress(apps, evs), 4);
    });

    test('goals sync and merge like applications', () {
      final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
      final g = Goal(id: 0, title: 'Apply to 40', target: 40, metric: 'applied');
      s.saveGoal(g);
      final cloud = s.exportState();
      // The cloud copy predates the edit below (a test can run both in the
      // same millisecond, which would tie the clocks).
      ((cloud['goals'] as List).first as Map)['u'] = g.uAt - 1;
      s.bumpGoal(g, 1); // manual counter edit after the snapshot
      s.applyRemoteState({...cloud, 'updatedAt': g.uAt + 1});
      expect(s.goals.single.count, 1, reason: 'the newer local edit is kept');
      final again = CadenceStore()..applyState(s.exportState());
      expect(again.goals.single.title, 'Apply to 40');
    });

    test('a manual counter never goes below zero', () {
      final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
      final g = Goal(id: 0, title: 'x');
      s.saveGoal(g);
      s.bumpGoal(g, -1);
      expect(g.count, 0);
    });
  });

  group('origin', () {
    test('new imports are marked imported; updates keep their origin', () {
      final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
      s.loadCareerStarter();
      final riot = s.applications.firstWhere((a) => a.company == 'Riot Games');
      expect(riot.from, 'you');
      // A sheet exported before origins existed: no origin column.
      final rows = parseCsv('id,company,status\n${riot.id},Riot Games,oa\n,Valve,to-apply\n');
      s.importApplications(applicationsFromCsv(rows));
      expect(s.applications.firstWhere((a) => a.company == 'Riot Games').from, 'you');
      expect(s.applications.firstWhere((a) => a.company == 'Valve').from, 'import');
    });

    test('origin round-trips through CSV and unknown values mean "you"', () {
      final e = TrackEvent(id: 3, name: 'From mail', origin: 'email');
      final back = eventsFromCsv(parseCsv(eventsToCsv([e]))).single;
      expect(back.from, 'email');
      expect(TrackEvent.fromJson({'name': 'x', 'origin': 'martians'}).from, 'you');
    });
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
      // Make the snapshot strictly older than the edit (a test can run both in
      // the same millisecond, which would tie the clocks).
      for (final a in (cloud['apps'] as List).cast<Map>()) {
        a['u'] = amazon.uAt - 1;
      }
      s.setAppStatus(amazon, 'applied');
      s.applyRemoteState({...cloud, 'updatedAt': amazon.uAt + 1});
      expect(s.applications.firstWhere((a) => a.company == 'Amazon').status, 'applied');
    });
  });
}
