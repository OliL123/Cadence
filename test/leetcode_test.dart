// LeetCode on the Career page: reading each source's answer, the history
// behind "this week" and goals, merging two devices' copies, and the panel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/store.dart';
import 'package:cadence/tracker/career_page.dart';
import 'package:cadence/tracker/leetcode.dart';
import 'package:cadence/tracker/tracker_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // A real answer (Oct 2026), trimmed.
  final graphql = {
    'data': {
      'matchedUser': {
        'username': 'DarkSparktheVoid',
        'submitStatsGlobal': {
          'acSubmissionNum': [
            {'difficulty': 'All', 'count': 1},
            {'difficulty': 'Easy', 'count': 1},
            {'difficulty': 'Medium', 'count': 0},
            {'difficulty': 'Hard', 'count': 0},
          ]
        },
        'userCalendar': {'streak': 1},
      },
      'recentAcSubmissionList': [
        {'title': 'Merge Sorted Array', 'titleSlug': 'merge-sorted-array', 'timestamp': '1791478706'}
      ],
    }
  };

  LeetCodeStats at(DateTime when, int total, {String user = 'me', Map<String, int> history = const {}}) =>
      LeetCodeStats(user: user, total: total, easy: total, medium: 0, hard: 0, fetchedAt: when, history: history);

  test('reads LeetCode\'s answer, and says when the user doesn\'t exist', () {
    final s = LeetCodeStats.fromGraphql('darksparkthevoid', graphql)!;
    expect((s.user, s.total, s.easy, s.medium, s.hard, s.streak), ('DarkSparktheVoid', 1, 1, 0, 0, 1));
    expect(s.recent.single.url, 'https://leetcode.com/problems/merge-sorted-array/');
    expect(LeetCodeStats.fromGraphql('nobody', {'data': {'matchedUser': null}}), isNull);
  });

  test('reads the community proxy\'s answer', () {
    final s = LeetCodeStats.fromProxy('me', {'solvedProblem': 12, 'easySolved': 8, 'mediumSolved': 3, 'hardSolved': 1},
        submissions: {
          'submission': [
            {'title': 'Two Sum', 'titleSlug': 'two-sum', 'timestamp': '1791478706'}
          ]
        })!;
    expect((s.total, s.easy, s.medium, s.hard, s.streak), (12, 8, 3, 1, null));
    expect(s.recent.single.title, 'Two Sum');
    expect(LeetCodeStats.fromProxy('x', {'errors': 'User not found'}), isNull);
  });

  test('history: each fetch records the day; "since" counts from before that day', () {
    var s = at(DateTime(2026, 10, 1), 10).withHistoryFrom(null);
    s = at(DateTime(2026, 10, 5), 14).withHistoryFrom(s);
    s = at(DateTime(2026, 10, 8), 20).withHistoryFrom(s);
    expect(s.history, {'2026-10-01': 10, '2026-10-05': 14, '2026-10-08': 20});
    expect(s.solvedSince(DateTime(2026, 10, 5)), 10, reason: '20 now − 10 before the 5th');
    expect(s.solvedSince(DateTime(2026, 9, 1)), 10, reason: 'no older snapshot: from the oldest');
    expect(at(DateTime(2026, 10, 8), 3, user: 'someone-else').withHistoryFrom(s).history.length, 1,
        reason: 'another user\'s history is not carried over');
  });

  test('two devices: the newer numbers win, histories combine', () {
    final a = at(DateTime(2026, 10, 8, 9), 20, history: {'2026-10-01': 10, '2026-10-08': 20});
    final b = at(DateTime(2026, 10, 8, 12), 21, history: {'2026-10-04': 12, '2026-10-08': 21});
    final m = LeetCodeStats.merge(a, b)!;
    expect(m.total, 21);
    expect(m.history, {'2026-10-01': 10, '2026-10-04': 12, '2026-10-08': 21});
  });

  test('the username and numbers sync; a LeetCode goal counts itself', () {
    final s = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    s.setLeetCodeUser(' DarkSparktheVoid ');
    s.setLeetCode(LeetCodeStats.fromGraphql('DarkSparktheVoid', graphql)!);
    final other = CadenceStore()..applyState({'tasks': <dynamic>[], 'updatedAt': 1});
    other.applyRemoteState(s.exportState());
    expect(other.leetcodeUser, 'DarkSparktheVoid');
    expect(other.leetcode!.total, 1);

    final goal = Goal(id: 1, title: 'Solve 150', target: 150, metric: 'leetcode');
    expect(goal.progress(const [], const [], leetcodeSolved: s.leetcodeSolvedSince), 1);
    expect(goal.progress(const [], const []), 0, reason: 'without LeetCode data');

    s.setLeetCodeUser('someone-else');
    expect(s.leetcode, isNull, reason: 'a different user\'s numbers are dropped');
  });

  Future<void> overview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store.applications = [Application(id: 1, company: 'Riot', role: 'SWE Intern')];
    store.trackEvents = [];
    store.goals = [];
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CareerPage())));
    await tester.pumpAndSettle();
  }

  testWidgets('not connected: the panel offers Connect', (tester) async {
    store.leetcodeUser = null;
    store.leetcode = null;
    await overview(tester);
    expect(find.text('LEETCODE'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('connected: total, this week, streak, difficulties, last solve', (tester) async {
    store.leetcodeUser = 'DarkSparktheVoid';
    final now = DateTime.now();
    store.leetcode = LeetCodeStats(
      user: 'DarkSparktheVoid',
      total: 42,
      easy: 25,
      medium: 15,
      hard: 2,
      streak: 4,
      fetchedAt: now, // fresh, so the panel doesn't fetch
      recent: [LeetCodeSolve('Merge Sorted Array', 'merge-sorted-array', now)],
      history: {isoDate(weekStart(now).subtract(const Duration(days: 1))): 37, isoDate(now): 42},
    );
    await overview(tester);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('solved · +5 this week · 4-day streak'), findsOneWidget);
    expect(find.text('Medium 15'), findsOneWidget);
    expect(find.textContaining('Last solved: Merge Sorted Array'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
