// Find: parsing each source, telling countries and kinds of role apart, the
// ranking, and the inbox flow (add / dismiss / closed postings / sync).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/career_page.dart';
import 'package:cadence/tracker/job_fetch.dart';
import 'package:cadence/tracker/job_sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final now = DateTime.now();
  int daysAgo(int d) => now.subtract(Duration(days: d)).millisecondsSinceEpoch ~/ 1000;

  Map<String, dynamic> simplify(String id, String co, String title,
          {List<String> locs = const ['SF'],
          bool active = true,
          List<String> terms = const ['Summer 2027'],
          String category = 'Software',
          List<String> degrees = const ["Bachelor's"],
          int posted = 0}) =>
      {
        'id': id, 'company_name': co, 'title': title, 'locations': locs, 'active': active,
        'is_visible': true, 'terms': terms, 'category': category, 'degrees': degrees,
        'url': 'https://example.com/$id', 'date_posted': posted == 0 ? daysAgo(3) : posted,
      };

  group('countries', () {
    test('every source\'s way of writing places', () {
      expect(countryOf('San Jose, CA'), 'US');
      expect(countryOf('NYC'), 'US');
      expect(countryOf('Remote in USA'), 'US');
      expect(countryOf('Cary,North Carolina,United States'), 'US');
      expect(countryOf('Los Angeles, USA'), 'US');
      expect(countryOf('Texas'), 'US');
      expect(countryOf('Melbourne, FL'), 'US', reason: 'Florida, not Australia');
      expect(countryOf('Melbourne VIC, Australia'), 'AU');
      expect(countryOf('Sydney, Australia'), 'AU');
      expect(countryOf('Hong Kong SAR'), 'HK');
      expect(countryOf('Singapore'), 'SG');
      expect(countryOf('Kuala Lumpur'), 'MY');
      expect(countryOf('Shanghai, China'), 'CN');
      expect(countryOf('Taipei'), 'TW');
      expect(countryOf('London, UK'), 'UK');
      expect(countryOf('London, ON, Canada'), 'CA');
      expect(countryOf('Toronto, ON, Canada'), 'CA');
      expect(countryOf('Berlin, Germany'), 'EU');
      expect(countryOf('Remote'), 'REMOTE');
      expect(countryOf('Istanbul'), 'OTHER');
    });
  });

  group('kinds of role', () {
    Posting p(String co, String title, {bool studio = false, String? cat}) => Posting(
        key: 'x', source: 'simplify', company: co, title: title, locations: const ['SF'],
        url: '', category: cat, gameStudio: studio);

    test('game dev: game-craft titles, or technical roles at studios', () {
      expect(interestsOf(p('Epic Games', 'Engine Programmer Intern')), containsAll(['game', 'swe']));
      expect(interestsOf(p('Booz', 'Gameplay Engineer Intern')), contains('game'));
      expect(interestsOf(p('Epic Games', 'Level Design Intern')), contains('game'));
      expect(interestsOf(p('Electronic Arts', 'Software Engineer Intern')), contains('game'));
      expect(interestsOf(p('Epic Games', 'Communications Intern')), {'other'},
          reason: 'a studio\'s non-technical roles are not game dev');
      expect(interestsOf(p('Epic Games', 'Product Management Intern')), {'product'});
    });

    test('software, ML and the rest', () {
      expect(interestsOf(p('Acme', 'Software Engineer Intern')), {'swe'});
      expect(interestsOf(p('Acme', 'SDET Intern')), {'swe'});
      expect(interestsOf(p('Acme', 'Machine Learning Intern')), contains('ml'));
      expect(interestsOf(p('Acme', 'Intern', cat: 'AI/ML/Data')), contains('data'));
      expect(interestsOf(p('Acme', 'Quant Trader Intern')), contains('quant'));
      expect(interestsOf(p('Acme', 'People Operations Intern')), {'other'});
    });
  });

  group('sources', () {
    test('Simplify: open roles for the term; closed ones remembered', () {
      final r = parseSimplify([
        simplify('a', 'Riot', 'Software Engineer Intern'),
        simplify('b', 'Old Co', 'SWE Intern', active: false),
        simplify('c', 'Next Co', 'SWE Intern', terms: ['Summer 2026']),
        simplify('d', 'Lab', 'Research Intern', degrees: ['PhD']),
      ]);
      expect(r.open.map((p) => p.company), ['Riot']);
      expect(r.closed, {'simplify:b'});
      expect(parseSimplify([simplify('d', 'Lab', 'R', degrees: ['PhD'])], hideAdvancedDegree: false)
          .open, hasLength(1));
    });

    test('Greenhouse: student roles for the term, with dates and deadlines', () {
      const b = FollowedBoard('greenhouse', 'riotgames', 'Riot Games', game: true);
      final ps = parseBoard(b, {
        'jobs': [
          {'id': 1, 'title': 'Software Engineering Intern - Summer 2027', 'location': {'name': 'Los Angeles, USA'},
            'absolute_url': 'u1', 'first_published': '2026-10-01T00:00:00Z', 'application_deadline': '2026-11-01T00:00:00Z'},
          {'id': 2, 'title': 'Senior Engineer', 'location': {'name': 'Singapore'}, 'absolute_url': 'u2'},
          {'id': 3, 'title': 'Gameplay Intern - Summer 2026', 'location': {'name': 'LA'}, 'absolute_url': 'u3'},
          {'id': 4, 'title': 'Engine Intern', 'location': {'name': 'Singapore; Shanghai, China'}, 'absolute_url': 'u4'},
        ],
      });
      expect(ps.map((p) => p.key), ['gh:riotgames:1', 'gh:riotgames:4']);
      expect(ps.first.deadline, '2026-11-01');
      expect(ps.first.posted, isNotNull);
      expect(ps.last.countries, {'SG', 'CN'});
      expect(ps.every((p) => p.gameStudio), isTrue);
    });

    test('Lever and Ashby: commitment / employment type count as student roles', () {
      final lever = parseBoard(const FollowedBoard('lever', 'larian', 'Larian'), [
        {'id': 'x', 'text': 'Gameplay Programmer', 'categories': {'commitment': 'Internship', 'location': 'Kuala Lumpur'},
          'country': 'MY', 'hostedUrl': 'h', 'createdAt': now.millisecondsSinceEpoch},
        {'id': 'y', 'text': 'Producer', 'categories': {'commitment': 'Full-time', 'location': 'Dublin'}, 'hostedUrl': 'h'},
      ]);
      expect(lever.single.countries, {'MY'});
      final ashby = parseBoard(const FollowedBoard('ashby', 'hoyoverse', 'HoYoverse', game: true), {
        'jobs': [
          {'id': 'a', 'title': 'Graphics Engineer', 'employmentType': 'Intern', 'location': 'Singapore',
            'jobUrl': 'j', 'publishedAt': '2026-10-05T00:00:00Z'},
          {'id': 'b', 'title': 'Graphics Engineer', 'employmentType': 'FullTime', 'location': 'Singapore', 'jobUrl': 'j'},
        ],
      });
      expect(ashby.single.key, 'ashby:hoyoverse:a');
      expect(ashby.single.countries, {'SG'});
    });

    test('careers links → boards', () {
      expect(FollowedBoard.fromLink('https://boards.greenhouse.io/riotgames')!.id, 'greenhouse:riotgames');
      expect(FollowedBoard.fromLink('https://job-boards.greenhouse.io/epicgames/jobs/123')!.id,
          'greenhouse:epicgames');
      expect(FollowedBoard.fromLink('jobs.lever.co/larian')!.id, 'lever:larian');
      expect(FollowedBoard.fromLink('https://jobs.ashbyhq.com/hoyoverse')!.id, 'ashby:hoyoverse');
      expect(FollowedBoard.fromLink('https://careers.example.myworkdayjobs.com/x'), isNull);
    });
  });

  group('ranking', () {
    final prefs = FindPrefs();
    final none = FindTaste.from(liked: const [], dismissed: const []);
    Posting p(String co, String title, {int age = 3, List<String> locs = const ['SF'], String src = 'simplify'}) =>
        Posting(key: '$co$title', source: src, company: co, title: title, locations: locs, url: '',
            posted: now.subtract(Duration(days: age)));

    test('game over software over ML; fresh over stale; finance sinks', () {
      int s(Posting x) => findScore(x, prefs, none);
      expect(s(p('Acme', 'Gameplay Programmer Intern')), greaterThan(s(p('Acme', 'Software Engineer Intern'))));
      expect(s(p('Acme', 'Software Engineer Intern')), greaterThan(s(p('Acme', 'Machine Learning Intern'))));
      expect(s(p('Acme', 'Software Engineer Intern', age: 2)),
          greaterThan(s(p('Acme', 'Software Engineer Intern', age: 50))));
      expect(s(p('Goldman Sachs', 'Software Engineer Intern')), lessThan(s(p('Acme', 'Software Engineer Intern'))));
    });

    test('the chips filter countries, interests and age', () {
      expect(findMatches(p('A', 'Software Engineer Intern', locs: ['Singapore']), prefs), isTrue);
      expect(findMatches(p('A', 'Software Engineer Intern', locs: ['London, UK']), prefs), isFalse);
      expect(findMatches(p('A', 'Hardware Engineer Intern'), prefs), isFalse);
      expect(findMatches(p('A', 'Software Engineer Intern', age: 90), prefs), isFalse);
    });

    test('taste: what you dismiss sinks, what you keep rises', () {
      final taste = FindTaste.from(
          liked: const [], dismissed: ['X — Frontend Web Developer Intern', 'Y — Web Developer Intern']);
      final web = p('Z', 'Web Developer Intern'), eng = p('Z', 'Engine Programmer Intern');
      expect(taste.bonus(web), lessThan(0));
      expect(taste.bonus(eng), 0);
    });
  });

  group('inbox actions', () {
    late CadenceStore s;
    final posting = Posting(
        key: 'gh:riotgames:1', source: 'greenhouse', company: 'Riot Games', title: 'Engine Programmer Intern',
        locations: const ['Los Angeles, USA'], url: 'https://riot/1', posted: now, gameStudio: true);
    setUp(() => s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1}));

    test('add makes a to-apply application that remembers its posting', () {
      final a = s.addPosting(posting);
      expect((a.status, a.track, a.origin, a.postingId, a.link),
          ('to-apply', 'game', 'cadence', 'gh:riotgames:1', 'https://riot/1'));
      expect(s.handledPostingKeys, contains('gh:riotgames:1'));
    });

    test('a closed posting flags its application; applied ones are left alone', () {
      final a = s.addPosting(posting);
      final b = s.addPosting(Posting(key: 'simplify:z', source: 'simplify', company: 'C', title: 'T',
          locations: const [], url: 'u'));
      s.setAppStatus(b, 'applied');
      expect(s.markPostingsClosed({'gh:riotgames:1', 'simplify:z'}), 1);
      expect(s.applications.firstWhere((x) => x.id == a.id).postingClosed, isTrue);
    });

    test('dismissals sync as a union; filters as a setting', () {
      s.dismissPosting(posting);
      final other = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
      other.dismissPosting(Posting(key: 'k2', source: 'simplify', company: 'Co', title: 'T',
          locations: const [], url: ''));
      other.applyRemoteState(s.exportState());
      expect(other.findDismissed.keys, containsAll(['gh:riotgames:1', 'k2']));
      s.setFindPrefs(FindPrefs(countries: ['SG']));
      other.applyRemoteState(s.exportState());
      expect(other.findPrefs.countries, ['SG']);
    });
  });

  testWidgets('Find lists postings best first; Add and Dismiss take them out', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.applications = [];
    store.trackEvents = [];
    store.findDismissed = {};
    store.findPrefs = FindPrefs(boards: []);
    final svc = FindService.instance;
    svc.postings = [
      Posting(key: 'simplify:1', source: 'simplify', company: 'Plain Co', title: 'Software Engineer Intern',
          locations: const ['SF'], url: 'u1', posted: now.subtract(const Duration(days: 40))),
      Posting(key: 'gh:epic:2', source: 'greenhouse', company: 'Epic Games', title: 'Gameplay Programmer Intern',
          locations: const ['Cary, NC'], url: 'u2', posted: now, gameStudio: true),
      Posting(key: 'simplify:3', source: 'simplify', company: 'London Co', title: 'Software Engineer Intern',
          locations: const ['London, UK'], url: 'u3', posted: now),
    ];
    svc.markFresh(); // fresh: no network refresh on open
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CareerPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();

    expect(find.text('London Co'), findsNothing, reason: 'UK is not a chosen country');
    final epic = tester.getTopLeft(find.text('Epic Games'));
    final plain = tester.getTopLeft(find.text('Plain Co'));
    expect(epic.dy < plain.dy || (epic.dy == plain.dy && epic.dx < plain.dx), isTrue,
        reason: 'the fresh game role ranks first');

    await tester.tap(find.byTooltip('Add to Applications').first);
    await tester.pumpAndSettle();
    expect(store.applications.single.company, 'Epic Games');
    expect(find.text('Epic Games'), findsNothing);

    await tester.tap(find.byTooltip('Dismiss').first);
    await tester.pumpAndSettle();
    expect(store.findDismissed.keys, ['simplify:1']);
    expect(find.text('Plain Co'), findsNothing);
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(find.text('Plain Co'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
