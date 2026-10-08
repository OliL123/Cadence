// LeetCode progress for the Career page: solved counts by difficulty, the
// streak, recent solves, and a day-by-day history of the total so "this
// week" and goals ("solve 150 by December") count themselves.
//
// LeetCode's API doesn't allow browser requests, so where it's read from
// depends on the platform:
//  * Android: straight from leetcode.com.
//  * Web: through our own Supabase function `leetcode` once it's deployed
//    (supabase/functions/leetcode), and until then a free community proxy
//    (alfa-leetcode-api) — slower and less certain, but no setup.
// The first that answers wins; if none do, the last numbers stay.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tracker_models.dart';

class LeetCodeSolve {
  final String title;
  final String slug;
  final DateTime at;
  const LeetCodeSolve(this.title, this.slug, this.at);

  String get url => 'https://leetcode.com/problems/$slug/';

  Map<String, dynamic> toJson() => {'t': title, 's': slug, 'a': at.millisecondsSinceEpoch};
  factory LeetCodeSolve.fromJson(Map<String, dynamic> j) => LeetCodeSolve(
      j['t'] as String, j['s'] as String, DateTime.fromMillisecondsSinceEpoch(j['a'] as int));
}

class LeetCodeStats {
  final String user;
  final int total, easy, medium, hard;
  final int? streak; // null when the source didn't say
  final DateTime fetchedAt;
  final List<LeetCodeSolve> recent;

  /// yyyy-mm-dd -> total solved as of that day (as last seen that day).
  final Map<String, int> history;

  const LeetCodeStats({
    required this.user,
    required this.total,
    required this.easy,
    required this.medium,
    required this.hard,
    this.streak,
    required this.fetchedAt,
    this.recent = const [],
    this.history = const {},
  });

  /// Solved since [from]: today's total minus the last total seen before
  /// that day. Without a snapshot from before it, counts from the oldest one
  /// we have (so a goal started today begins at 0, not at your all-time total).
  int solvedSince(DateTime from) {
    final cut = isoDate(from);
    final before = history.keys.where((d) => d.compareTo(cut) < 0).toList()..sort();
    if (before.isNotEmpty) return (total - history[before.last]!).clamp(0, total);
    final all = history.keys.toList()..sort();
    if (all.isEmpty) return 0;
    return (total - history[all.first]!).clamp(0, total);
  }

  int get thisWeek => solvedSince(weekStart(DateTime.now()));

  /// This fetch's numbers, with today's total added to [history] (kept to
  /// the last 400 days).
  LeetCodeStats withHistoryFrom(LeetCodeStats? old) {
    final h = <String, int>{if (old != null && old.user == user) ...old.history};
    h[isoDate(fetchedAt)] = total;
    final keep = (h.keys.toList()..sort());
    while (keep.length > 400) {
      h.remove(keep.removeAt(0));
    }
    return LeetCodeStats(
      user: user,
      total: total,
      easy: easy,
      medium: medium,
      hard: hard,
      streak: streak ?? (old?.user == user ? old?.streak : null),
      fetchedAt: fetchedAt,
      recent: recent.isNotEmpty ? recent : (old?.user == user ? old!.recent : const []),
      history: h,
    );
  }

  /// Two devices' copies → one: the newer numbers, both histories.
  static LeetCodeStats? merge(LeetCodeStats? a, LeetCodeStats? b) {
    if (a == null) return b;
    if (b == null || a.user != b.user) return a;
    final newer = a.fetchedAt.isAfter(b.fetchedAt) ? a : b;
    final older = identical(newer, a) ? b : a;
    final h = {...older.history};
    newer.history.forEach((d, n) => h[d] = h[d] == null || n > h[d]! ? n : h[d]!);
    return LeetCodeStats(
      user: newer.user,
      total: newer.total,
      easy: newer.easy,
      medium: newer.medium,
      hard: newer.hard,
      streak: newer.streak,
      fetchedAt: newer.fetchedAt,
      recent: newer.recent,
      history: h,
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user,
        'total': total,
        'easy': easy,
        'medium': medium,
        'hard': hard,
        if (streak != null) 'streak': streak,
        'at': fetchedAt.millisecondsSinceEpoch,
        'recent': recent.map((r) => r.toJson()).toList(),
        'history': history,
      };

  factory LeetCodeStats.fromJson(Map<String, dynamic> j) => LeetCodeStats(
        user: j['user'] as String,
        total: (j['total'] as num).toInt(),
        easy: (j['easy'] as num).toInt(),
        medium: (j['medium'] as num).toInt(),
        hard: (j['hard'] as num).toInt(),
        streak: (j['streak'] as num?)?.toInt(),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        recent: [
          for (final r in (j['recent'] as List? ?? const []))
            LeetCodeSolve.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
        history: Map<String, int>.from(
            (j['history'] as Map? ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt()))),
      );

  /// LeetCode's own GraphQL answer (direct, or via our function).
  static LeetCodeStats? fromGraphql(String user, Map<String, dynamic> body, {DateTime? now}) {
    final data = body['data'] as Map?;
    final u = data?['matchedUser'] as Map?;
    if (u == null) return null; // no such user
    final counts = <String, int>{};
    for (final c in ((u['submitStatsGlobal'] as Map?)?['acSubmissionNum'] as List? ?? const [])) {
      counts['${c['difficulty']}'] = (c['count'] as num).toInt();
    }
    return LeetCodeStats(
      user: '${u['username'] ?? user}',
      total: counts['All'] ?? 0,
      easy: counts['Easy'] ?? 0,
      medium: counts['Medium'] ?? 0,
      hard: counts['Hard'] ?? 0,
      streak: ((u['userCalendar'] as Map?)?['streak'] as num?)?.toInt(),
      fetchedAt: now ?? DateTime.now(),
      recent: _recent(data?['recentAcSubmissionList']),
    );
  }

  static List<LeetCodeSolve> _recent(dynamic list) => [
        for (final r in (list as List? ?? const []))
          if (r is Map)
            LeetCodeSolve(
              '${r['title']}',
              '${r['titleSlug']}',
              DateTime.fromMillisecondsSinceEpoch(
                  (int.tryParse('${r['timestamp']}') ?? 0) * 1000),
            ),
      ];

  /// The community proxy's /solved (+ /acSubmission) answers.
  static LeetCodeStats? fromProxy(String user, Map<String, dynamic> solved,
      {dynamic submissions, DateTime? now}) {
    if (solved['solvedProblem'] == null) return null;
    return LeetCodeStats(
      user: user,
      total: (solved['solvedProblem'] as num).toInt(),
      easy: (solved['easySolved'] as num?)?.toInt() ?? 0,
      medium: (solved['mediumSolved'] as num?)?.toInt() ?? 0,
      hard: (solved['hardSolved'] as num?)?.toInt() ?? 0,
      fetchedAt: now ?? DateTime.now(),
      recent: _recent(submissions is Map ? submissions['submission'] : submissions),
    );
  }
}

const _query = r'''
query($u: String!) {
  matchedUser(username: $u) {
    username
    submitStatsGlobal { acSubmissionNum { difficulty count } }
    userCalendar { streak }
  }
  recentAcSubmissionList(username: $u, limit: 5) { title titleSlug timestamp }
}''';

/// Read [user]'s stats from whichever source answers first (see top).
/// Returns null when the user doesn't exist; throws when nothing could be
/// reached.
Future<LeetCodeStats?> fetchLeetCode(String user) async {
  final errors = <String>[];

  Future<LeetCodeStats?> direct() async {
    final r = await http
        .post(Uri.parse('https://leetcode.com/graphql'),
            headers: {'Content-Type': 'application/json', 'Referer': 'https://leetcode.com'},
            body: jsonEncode({'query': _query, 'variables': {'u': user}}))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return LeetCodeStats.fromGraphql(user, jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  Future<LeetCodeStats?> ours() async {
    final r = await Supabase.instance.client.functions
        .invoke('leetcode', body: {'username': user})
        .timeout(const Duration(seconds: 15));
    final d = r.data;
    if (d is! Map) throw 'no answer';
    return LeetCodeStats.fromGraphql(user, Map<String, dynamic>.from(d));
  }

  Future<LeetCodeStats?> proxy() async {
    const base = 'https://alfa-leetcode-api.onrender.com';
    final s = await http.get(Uri.parse('$base/$user/solved')).timeout(const Duration(seconds: 40));
    if (s.statusCode != 200) throw 'HTTP ${s.statusCode}';
    dynamic subs;
    try {
      final a = await http
          .get(Uri.parse('$base/$user/acSubmission?limit=5'))
          .timeout(const Duration(seconds: 20));
      if (a.statusCode == 200) subs = jsonDecode(utf8.decode(a.bodyBytes));
    } catch (_) {
      // counts without the recent list are still worth having
    }
    final j = jsonDecode(utf8.decode(s.bodyBytes));
    return j is Map ? LeetCodeStats.fromProxy(user, Map<String, dynamic>.from(j), submissions: subs) : null;
  }

  for (final (name, source) in [
    if (!kIsWeb) ('LeetCode', direct),
    ('Cadence function', ours),
    ('community proxy', proxy),
  ]) {
    try {
      return await source();
    } catch (e) {
      errors.add('$name: $e');
    }
  }
  throw errors.join('; ');
}
