// Find's network side: download the sources, keep a local cache so the
// inbox opens instantly (and offline), and note which postings are new.
//
// The cache is per device, not synced: it's a copy of public data that any
// device can fetch again. What syncs is what you did with it — the filters,
// dismissals and added applications live in the store.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../store.dart';
import 'job_sources.dart';

const simplifyUrl =
    'https://raw.githubusercontent.com/SimplifyJobs/Summer2027-Internships/dev/.github/scripts/listings.json';

class FindService extends ChangeNotifier {
  FindService._();
  static final instance = FindService._();

  static const _key = 'cadence_find_v1';

  List<Posting> postings = [];
  DateTime? fetchedAt;
  bool loading = false;

  /// Sources that failed on the last refresh: name -> reason.
  Map<String, String> errors = {};

  /// When each posting was first seen here, for the NEW badge.
  Map<String, int> _firstSeen = {};

  /// The previous time Find was opened: anything first seen after it is new.
  int _lastVisit = 0, _prevVisit = 0;

  bool _loaded = false;

  bool isNew(Posting p) => (_firstSeen[p.key] ?? 0) > _prevVisit && _prevVisit > 0;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      postings = [
        for (final p in (j['postings'] as List? ?? const []))
          Posting.fromJson(Map<String, dynamic>.from(p as Map)),
      ];
      fetchedAt = j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      _firstSeen = Map<String, int>.from(j['seen'] as Map? ?? const {});
      _lastVisit = (j['visit'] as int?) ?? 0;
      notifyListeners();
    } catch (_) {
      // a bad cache just means fetching again
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _key,
          jsonEncode({
            'at': fetchedAt?.millisecondsSinceEpoch,
            'visit': _lastVisit,
            'seen': _firstSeen,
            'postings': postings.map((x) => x.toJson()).toList(),
          }));
    } catch (_) {
      // storage full or blocked: the inbox still works for this session
    }
  }

  /// Opening Find: remember the last visit (for NEW), and refresh if the
  /// copy here is older than [maxAge].
  Future<void> open({Duration maxAge = const Duration(hours: 6)}) async {
    await load();
    _prevVisit = _lastVisit;
    _lastVisit = DateTime.now().millisecondsSinceEpoch;
    unawaited(_save());
    if (fetchedAt == null || DateTime.now().difference(fetchedAt!) > maxAge) {
      await refresh();
    } else {
      notifyListeners();
    }
  }

  Future<dynamic> _getJson(String url) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    errors = {};
    notifyListeners();
    final prefs = store.findPrefs;
    final found = <Posting>[];
    final closed = <String>{};
    final fetchedBoards = <String>{};

    Future<void> simplify() async {
      try {
        final raw = await _getJson(simplifyUrl) as List;
        final r = parseSimplify(raw,
            term: prefs.term, hideAdvancedDegree: prefs.hideAdvancedDegree);
        found.addAll(r.open);
        closed.addAll(r.closed);
      } catch (e) {
        errors['SimplifyJobs'] = '$e';
      }
    }

    Future<void> board(FollowedBoard b) async {
      try {
        found.addAll(parseBoard(b, await _getJson(b.feedUrl), term: prefs.term));
        fetchedBoards.add('${b.ats == 'greenhouse' ? 'gh' : b.ats}:${b.slug}:');
      } catch (e) {
        errors[b.name] = '$e';
      }
    }

    await Future.wait([
      if (prefs.useSimplify) simplify(),
      for (final b in prefs.boards) board(b),
    ]);

    // One copy per role: a company's own board beats the same role on
    // Simplify (exact dates, deadlines).
    final byKey = <String, Posting>{};
    final byRole = <String, String>{};
    String roleKey(Posting p) =>
        '${p.company.toLowerCase().trim()}|${p.title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()}';
    for (final p in found.where((p) => p.source != 'simplify')) {
      byKey[p.key] = p;
      byRole[roleKey(p)] = p.key;
    }
    for (final p in found.where((p) => p.source == 'simplify')) {
      if (!byRole.containsKey(roleKey(p))) byKey[p.key] = p;
    }

    // Keep a source's previous postings if it failed this time, rather than
    // emptying the inbox over a network blip.
    final failedPrefixes = {
      if (errors.containsKey('SimplifyJobs')) 'simplify:',
      for (final b in prefs.boards)
        if (errors.containsKey(b.name)) '${b.ats == 'greenhouse' ? 'gh' : b.ats}:${b.slug}:',
    };
    for (final p in postings) {
      if (failedPrefixes.any(p.key.startsWith)) byKey.putIfAbsent(p.key, () => p);
    }

    postings = byKey.values.toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in postings) {
      _firstSeen.putIfAbsent(p.key, () => now);
    }
    _firstSeen.removeWhere((k, _) => !byKey.containsKey(k));

    // Applications from a board we just read whose posting is gone: closed.
    for (final a in store.applications) {
      final id = a.postingId;
      if (id == null) continue;
      if (fetchedBoards.any(id.startsWith) && !byKey.containsKey(id)) closed.add(id);
    }
    store.markPostingsClosed(closed);

    fetchedAt = DateTime.now();
    loading = false;
    notifyListeners();
    await _save();
  }

  /// Check a careers link before following it: the board, with its name if
  /// the feed says, or an error message.
  static Future<(FollowedBoard?, String?)> resolve(String link, {String? name}) async {
    final b = FollowedBoard.fromLink(link, name: name);
    if (b == null) {
      return (
        null,
        'Find can follow Greenhouse, Lever and Ashby job boards — paste a link like '
            'boards.greenhouse.io/riotgames, jobs.lever.co/larian or jobs.ashbyhq.com/hoyoverse.'
      );
    }
    try {
      final r = await http.get(Uri.parse(b.feedUrl)).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return (null, 'That board didn\'t answer (HTTP ${r.statusCode}).');
      var title = name;
      if (title == null && b.ats == 'greenhouse') {
        final jobs = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['jobs'] as List?;
        if (jobs != null && jobs.isNotEmpty) title = (jobs.first as Map)['company_name'] as String?;
      }
      return (FollowedBoard(b.ats, b.slug, title ?? b.slug), null);
    } catch (e) {
      return (null, 'Couldn\'t reach that board: $e');
    }
  }
}
