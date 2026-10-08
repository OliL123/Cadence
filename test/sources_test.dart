// Find's extra sources: the SpeedyApply and vanshb03 GitHub lists, and
// SmartRecruiters / Workable company boards.
import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/tracker/job_sources.dart';

void main() {
  group('SpeedyApply tables', () {
    // Shaped like the real README: a US table with a Salary column, then a
    // Quant section, and an international table without Salary.
    const md = '''
# 2027 Software Engineering Internship & New Grad Positions
### FAANG+
| Company | Position | Location | Salary | Posting | Age |
|---|---|---|---|---|---|
| <a href="https://www.lyft.com"><strong>Lyft</strong></a> | Software Engineer Intern - Summer 2027 | San Francisco, CA | \$58/hr | <a href="https://app.careerpuck.com/job-board/lyft/job/88?gh_jid=88"><img src="x" alt="Apply" width="70"/></a> | 6d |
| <a href="https://x.com"><strong>Closed Co</strong></a> | SWE Intern | Austin, TX | \$40/hr | 🔒 | 3d |
| <a href="https://y.com"><strong>Old Co</strong></a> | SWE Intern - Summer 2026 | Austin, TX | \$40/hr | <a href="https://y.com/job/1">Apply</a> | 90d |
### Quant
| Company | Position | Location | Salary | Posting | Age |
|---|---|---|---|---|---|
| <a href="https://citadel.com"><strong>Citadel</strong></a> | Software Engineer - Intern - Asia | Hong Kong +1 | \$80/hr | <a href="https://www.citadel.com/careers/details/swe-intern-asia/">Apply</a> | 2w |
''';

    test('reads rows by their header, skipping closed and other-term roles', () {
      final ps = parseSpeedyApply(md, now: DateTime(2026, 10, 8));
      expect(ps.map((p) => p.company), ['Lyft', 'Citadel']);
      final lyft = ps.first;
      expect(lyft.title, 'Software Engineer Intern - Summer 2027');
      expect(lyft.locations, ['San Francisco, CA']);
      expect(lyft.url, 'https://app.careerpuck.com/job-board/lyft/job/88?gh_jid=88');
      expect(lyft.posted, DateTime(2026, 10, 2), reason: '6d before 8 Oct');
      expect(lyft.source, 'speedyapply');
      expect(lyft.countries, {'US'});
    });

    test('Quant section and "+1" locations', () {
      final citadel = parseSpeedyApply(md, now: DateTime(2026, 10, 8)).last;
      expect(citadel.locations, ['Hong Kong'], reason: '"+1" more cities is dropped');
      expect(citadel.countries, {'HK'});
      expect(citadel.posted, DateTime(2026, 9, 24), reason: '2w');
      expect(interestsOf(citadel), contains('quant'));
    });
  });

  test('the vanshb03 list: Simplify\'s format with a bare season', () {
    final r = parseSimplify([
      {'id': 'a', 'active': true, 'is_visible': true, 'season': 'Summer', 'company_name': 'Point72',
        'title': 'Quantitative Developer Intern', 'locations': ['New York, NY'], 'url': 'https://p72'},
      {'id': 'b', 'active': true, 'is_visible': true, 'season': 'Fall', 'company_name': 'X',
        'title': 'SWE Intern', 'locations': ['NYC'], 'url': 'u'},
      {'id': 'c', 'active': false, 'season': 'Summer', 'company_name': 'Y', 'title': 'Intern',
        'locations': const [], 'url': 'u'},
    ], source: 'vansh');
    expect(r.open.map((p) => p.key), ['vansh:a']);
    expect(r.open.single.source, 'vansh');
    expect(r.closed, {'vansh:c'});
  });

  group('SmartRecruiters', () {
    const ubi = FollowedBoard('smartrecruiters', 'Ubisoft2', 'Ubisoft', game: true);
    final feed = {
      'content': [
        {
          'id': '744000154392949',
          'name': 'VFX Artist Intern',
          'releasedDate': '2026-10-08T09:49:25.733Z',
          'location': {'city': 'Singapore', 'region': '', 'country': 'sg', 'fullLocation': 'Singapore, , Singapore'},
          'typeOfEmployment': {'label': 'Full-time'},
          'experienceLevel': {'id': 'internship'},
        },
        {
          'id': '1',
          'name': 'Lead Gameplay Programmer',
          'location': {'city': 'Montreal', 'country': 'ca'},
          'typeOfEmployment': {'label': 'Full-time'},
          'experienceLevel': {'id': 'mid_senior_level'},
        },
      ]
    };

    test('internships only, with a clean location and the job page', () {
      final ps = parseBoard(ubi, feed);
      expect(ps, hasLength(1));
      final p = ps.single;
      expect(p.key, 'sr:Ubisoft2:744000154392949');
      expect(p.locations, ['Singapore, Singapore']);
      expect(p.countries, {'SG'});
      expect(p.url, 'https://jobs.smartrecruiters.com/Ubisoft2/744000154392949');
      expect(p.gameStudio, isTrue);
      expect(p.sponsorChecked, isFalse, reason: 'the list has no description');
    });

    test('its description is read from the job\'s own API entry', () {
      final p = parseBoard(ubi, feed).single;
      final src = descriptionSource(p)!;
      expect(src.url, 'https://api.smartrecruiters.com/v1/companies/Ubisoft2/postings/744000154392949');
      final text = descriptionFrom('smartrecruiters', {
        'jobAd': {
          'sections': {
            'jobDescription': {'text': '<p>Make effects.</p>'},
            'additionalInformation': {'text': '<p>We are unable to sponsor visas.</p>'},
          }
        }
      });
      expect(scanSponsorship(text!)?.flag, 'no-sponsor');
    });

    test('list links to SmartRecruiters jobs are readable too', () {
      final p = Posting(
          key: 'speedyapply:x', source: 'speedyapply', company: 'Visa', title: 'Intern',
          locations: const [], url: 'https://jobs.smartrecruiters.com/Visa/744000099999999-software-intern');
      expect(descriptionSource(p)?.url,
          'https://api.smartrecruiters.com/v1/companies/Visa/postings/744000099999999');
    });
  });

  test('Workable: internships, scanned from the feed\'s own description', () {
    const b = FollowedBoard('workable', 'rovio', 'Rovio', game: true);
    final ps = parseBoard(b, {
      'name': 'Rovio',
      'jobs': [
        {
          'shortcode': 'AB12',
          'title': 'Game Design Intern',
          'employment_type': 'Internship',
          'url': 'https://apply.workable.com/j/AB12',
          'published_on': '2026-10-01',
          'locations': [
            {'city': 'Espoo', 'region': 'Uusimaa', 'country': 'Finland', 'hidden': false}
          ],
          'description': '<p>Design levels.</p><p>Visa sponsorship is available.</p>',
        },
        {'shortcode': 'CD34', 'title': 'Senior Producer', 'employment_type': 'Full-time', 'locations': const []},
      ]
    });
    expect(ps.single.key, 'wk:rovio:AB12');
    expect(ps.single.locations, ['Espoo, Uusimaa, Finland']);
    expect(ps.single.sponsorChecked, isTrue);
    expect(ps.single.sponsor?.flag, 'sponsors');
  });

  test('following by link: SmartRecruiters and Workable', () {
    final sr = FollowedBoard.fromLink('https://jobs.smartrecruiters.com/Ubisoft2/744000154392949')!;
    expect((sr.ats, sr.slug), ('smartrecruiters', 'Ubisoft2'));
    expect(FollowedBoard.fromLink('careers.smartrecruiters.com/Gameloft')?.slug, 'Gameloft');
    final wk = FollowedBoard.fromLink('https://apply.workable.com/rovio/')!;
    expect((wk.ats, wk.slug), ('workable', 'rovio'));
    expect(FollowedBoard.fromLink('https://apply.workable.com/j/AB12'), isNull,
        reason: 'a single job link doesn\'t name the company board');
    expect(sr.keyPrefix, 'sr:Ubisoft2:');
    expect(const FollowedBoard('greenhouse', 'riotgames', 'Riot').keyPrefix, 'gh:riotgames:');
  });

  test('prefs: both extra lists on by default, and they round-trip', () {
    expect(FindPrefs().lists, ['speedyapply', 'vansh']);
    final p = FindPrefs()..lists = ['speedyapply'];
    expect(FindPrefs.fromJson(p.toJson()).lists, ['speedyapply']);
  });
}
