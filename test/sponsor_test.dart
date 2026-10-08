// Find's sponsorship scan: what job descriptions say about visa sponsorship.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/job_sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  String? flag(String text) => scanSponsorship(text)?.flag;

  group('scanSponsorship', () {
    test('no sponsorship, in the ways postings say it', () {
      for (final t in [
        'We are unable to sponsor visas for this role.',
        'Company X will not sponsor applicants for work visa status.',
        'This position does not offer visa sponsorship.',
        'Applicants must be authorized to work in the U.S. without sponsorship.',
        'Candidates must be able to work without current or future sponsorship.',
        'Visa sponsorship is not available for this position.',
        'There is no visa sponsorship for this internship.',
        'Candidates who require sponsorship will not be considered.',
        "We can't sponsor work authorization.",
        'Students on CPT or OPT are not eligible for this program.',
      ]) {
        expect(flag(t), 'no-sponsor', reason: t);
      }
    });

    test('citizens only and clearance outrank plain no-sponsorship', () {
      expect(flag('Must be a U.S. citizen. We do not sponsor visas.'), 'citizens');
      expect(flag('US citizenship is required for this role.'), 'citizens');
      expect(flag('This role is only open to United States citizens.'), 'citizens');
      // The Nuclear Company's real wording, via SimplifyJobs.
      final tnc = scanSponsorship('Due to export controls, U.S. person (citizen or lawful '
          'permanent resident) is required, and TNC does not provide visa sponsorship for '
          'these roles.')!;
      expect(tnc.flag, 'citizens');
      expect(tnc.why, startsWith('Due to export controls, US person'),
          reason: '"U.S." must not cut the quoted sentence');
      expect(flag('An active Secret security clearance is required.'), 'clearance');
      expect(flag('Candidates must be able to obtain and maintain a security clearance.'), 'clearance');
    });

    test('positive only in a visa context', () {
      expect(flag('We will sponsor H-1B visas for qualified candidates.'), 'sponsors');
      expect(flag('Visa sponsorship is available.'), 'sponsors');
      expect(flag('CPT is welcome for international students.'), 'sponsors');
      expect(flag('We sponsor hackathons and game jams every year.'), isNull,
          reason: 'not about visas');
      expect(flag('Join our team building games loved by millions.'), isNull);
    });

    test('bullets are separate sentences: no match across two of them', () {
      expect(flag('<ul><li>Not required: a CS degree</li><li>We sponsor hackathons</li></ul>'),
          isNull);
      // Riot's real Summer 2027 intern posting, as Greenhouse sends it.
      final s = scanSponsorship('&lt;h3&gt;Work Authorization&lt;/h3&gt;&lt;p&gt;Candidates must be '
          'legally authorized to work in the United States for the duration of the '
          'program.&lt;/p&gt;&lt;p&gt;This position is not eligible for visa sponsorship. We do '
          'not sponsor visas for this position or internship conversions.&lt;/p&gt;'
          '&lt;p&gt;Relocation &amp;amp; support&amp;nbsp;included&lt;/p&gt;')!;
      expect(s.flag, 'no-sponsor');
      expect(s.why, 'This position is not eligible for visa sponsorship.');
      expect(descriptionText('a&amp;amp;b&amp;nbsp;c'), 'a&b c', reason: 'double-escaped entities');
    });

    test('reads HTML escaped inside JSON, and quotes the sentence', () {
      const gh = '&lt;p&gt;Great team.&lt;/p&gt;&lt;p&gt;We are &lt;strong&gt;unable to '
          'sponsor&lt;/strong&gt; visas for this role.&lt;/p&gt;';
      final s = scanSponsorship(gh)!;
      expect(s.flag, 'no-sponsor');
      expect(s.why, 'We are unable to sponsor visas for this role.');
    });
  });

  test('the stricter finding wins; nothing never erases a finding', () {
    const no = SponsorCheck('no-sponsor', 'a');
    const yes = SponsorCheck('sponsors', 'b');
    const cit = SponsorCheck('citizens', 'c');
    expect(stricterSponsor(yes, no), no);
    expect(stricterSponsor(no, cit), cit);
    expect(stricterSponsor(no, null), no);
    expect(stricterSponsor(null, yes), yes);
  });

  test('SimplifyJobs\' own field', () {
    expect(simplifySponsor('Does Not Offer Sponsorship')?.flag, 'no-sponsor');
    expect(simplifySponsor('U.S. Citizenship is Required')?.flag, 'citizens');
    expect(simplifySponsor('Offers Sponsorship')?.flag, 'sponsors');
    expect(simplifySponsor('Other'), isNull);
  });

  group('where a description can be read', () {
    Posting p(String key, String url, {String source = 'simplify'}) => Posting(
        key: key, source: source, company: 'X', title: 'Intern', locations: const ['NYC'], url: url);

    test('followed Greenhouse boards: the job API', () {
      expect(descriptionSource(p('gh:epicgames:123', 'https://x', source: 'greenhouse'))?.url,
          'https://boards-api.greenhouse.io/v1/boards/epicgames/jobs/123');
    });

    test('SimplifyJobs links to Greenhouse, Lever and Ashby', () {
      expect(
          descriptionSource(p('simplify:1',
                  'https://job-boards.greenhouse.io/transmarketgroup/jobs/5151569007?gh_jid=5151569007'))
              ?.url,
          'https://boards-api.greenhouse.io/v1/boards/transmarketgroup/jobs/5151569007');
      expect(
          descriptionSource(p('simplify:2',
                  'https://jobs.lever.co/palantir/d5486403-c050-4920-b2e0-91b69b61ebb2/apply'))
              ?.url,
          'https://api.lever.co/v0/postings/palantir/d5486403-c050-4920-b2e0-91b69b61ebb2');
      final a = descriptionSource(
          p('simplify:3', 'https://jobs.ashbyhq.com/ramp/0d1e7a2b-1111-2222-3333-444455556666'))!;
      expect(a.ats, 'ashby');
      expect(a.id, '0d1e7a2b-1111-2222-3333-444455556666');
    });

    test('anything else (e.g. Workday) is left alone', () {
      expect(descriptionSource(p('simplify:4', 'https://ea.wd1.myworkdayjobs.com/x/job/123')), isNull);
    });
  });

  test('Lever and Ashby boards are scanned as they are parsed', () {
    final lever = parseBoard(const FollowedBoard('lever', 'acme', 'Acme'), [
      {
        'id': 'a1',
        'text': 'Software Engineering Intern',
        'hostedUrl': 'https://jobs.lever.co/acme/a1',
        'categories': {'location': 'New York', 'commitment': 'Intern'},
        'descriptionPlain': 'Build things. We are not able to sponsor visas.',
      }
    ]);
    expect(lever.single.sponsorChecked, isTrue);
    expect(lever.single.sponsor?.flag, 'no-sponsor');
  });

  test('a finding survives the cache round trip', () {
    final p = Posting(
        key: 'gh:a:1', source: 'greenhouse', company: 'A', title: 'Intern', locations: const ['NYC'],
        url: 'u', sponsor: const SponsorCheck('citizens', 'US citizens only.'), sponsorChecked: true);
    final back = Posting.fromJson(p.toJson());
    expect(back.sponsor?.flag, 'citizens');
    expect(back.sponsor?.why, 'US citizens only.');
    expect(back.sponsorChecked, isTrue);
  });

  test('the filter hides warnings only when asked', () {
    final p = Posting(
        key: 'gh:a:1', source: 'greenhouse', company: 'A', title: 'Software Engineer Intern',
        locations: const ['New York, NY'], url: 'u', posted: DateTime.now(),
        sponsor: const SponsorCheck('no-sponsor', 'x'));
    final prefs = FindPrefs();
    expect(findMatches(p, prefs), isTrue);
    expect(findMatches(p, prefs..hideNoSponsor = true), isFalse);
    p.sponsor = const SponsorCheck('sponsors', 'y');
    expect(findMatches(p, prefs), isTrue, reason: 'a positive finding is never hidden');
  });

  test('adding a posting carries its finding into the application', () {
    final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    final a = s.addPosting(Posting(
        key: 'gh:a:1', source: 'greenhouse', company: 'A', title: 'Intern', locations: const ['NYC'],
        url: 'u', sponsor: const SponsorCheck('no-sponsor', 'We do not sponsor.')));
    expect(a.sponsorship, 'no-sponsorship');
    expect(a.notes, contains('We do not sponsor.'));
  });
}
