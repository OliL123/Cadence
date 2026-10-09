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
// SpeedyApply: US internships (README) and international ones.
const speedyApplyUrls = [
  'https://raw.githubusercontent.com/speedyapply/2027-SWE-College-Jobs/main/README.md',
  'https://raw.githubusercontent.com/speedyapply/2027-SWE-College-Jobs/main/INTERN_INTL.md',
];

/// Each list's name in error messages, and its posting-key prefix.
const _listName = {'simplify': 'SimplifyJobs', 'speedyapply': 'SpeedyApply'};

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

  /// Which sources the cached postings came from. When it no longer matches
  /// the settings (a new source in an update, or one switched on elsewhere),
  /// opening Find fetches again instead of waiting out the cache's age.
  String _sourcesSig = '';
  /// Treat the postings held now as just fetched from the current sources
  /// (tests set [postings] by hand and must not trigger a network refresh).
  @visibleForTesting
  void markFresh() {
    fetchedAt = DateTime.now();
    _sourcesSig = _sigOf(store.findPrefs);
  }

  static String _sigOf(FindPrefs p) => [
        if (p.useSimplify) 'simplify',
        ...p.lists,
        ...p.boards.map((b) => b.id),
      ].join(',');

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
      _sourcesSig = (j['sig'] as String?) ?? '';
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
            'sig': _sourcesSig,
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
    if (fetchedAt == null ||
        DateTime.now().difference(fetchedAt!) > maxAge ||
        _sourcesSig != _sigOf(store.findPrefs)) {
      await refresh();
    } else {
      notifyListeners();
      unawaited(checkSponsorship()); // finish any reads a closed tab left
    }
  }

  Future<String> _getText(String url) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return utf8.decode(r.bodyBytes);
  }

  Future<dynamic> _getJson(String url) async => jsonDecode(await _getText(url));

  /// A board's feed. SmartRecruiters pages 100 at a time, so its pages are
  /// joined (up to 1,000 postings) into one {'content': [...]}.
  Future<dynamic> _boardFeed(FollowedBoard b) async {
    if (b.ats != 'smartrecruiters') return _getJson(b.feedUrl);
    final all = <dynamic>[];
    for (var offset = 0; offset < 1000; offset += 100) {
      final page = await _getJson('${b.feedUrl}&offset=$offset') as Map;
      final content = page['content'] as List? ?? const [];
      all.addAll(content);
      if (content.length < 100 || all.length >= ((page['totalFound'] as num?) ?? 0)) break;
    }
    return {'content': all};
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
        final r = parseSimplify(await _getJson(simplifyUrl) as List,
            term: prefs.term, hideAdvancedDegree: prefs.hideAdvancedDegree);
        found.addAll(r.open);
        closed.addAll(r.closed);
      } catch (e) {
        errors[_listName['simplify']!] = '$e';
      }
    }

    Future<void> speedyApply() async {
      try {
        final pages = await Future.wait(speedyApplyUrls.map(_getText));
        for (final md in pages) {
          found.addAll(parseSpeedyApply(md, term: prefs.term));
        }
      } catch (e) {
        errors[_listName['speedyapply']!] = '$e';
      }
    }

    Future<void> board(FollowedBoard b) async {
      try {
        found.addAll(parseBoard(b, await _boardFeed(b), term: prefs.term));
        fetchedBoards.add(b.keyPrefix);
      } catch (e) {
        errors[b.name] = '$e';
      }
    }

    await Future.wait([
      if (prefs.useSimplify) simplify(),
      if (prefs.lists.contains('speedyapply')) speedyApply(),
      for (final b in prefs.boards) board(b),
    ]);

    // One copy per role: a company's own board beats the lists (exact dates,
    // deadlines), and among the lists the first in [findListSources] wins.
    final byKey = <String, Posting>{};
    final byRole = <String>{};
    String roleKey(Posting p) =>
        '${p.company.toLowerCase().trim()}|${p.title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()}';
    for (final p in found.where((p) => !findListSources.contains(p.source))) {
      byKey[p.key] = p;
      byRole.add(roleKey(p));
    }
    for (final source in findListSources) {
      for (final p in found.where((p) => p.source == source)) {
        if (byRole.add(roleKey(p))) byKey[p.key] = p;
      }
    }

    // Keep a source's previous postings if it failed this time, rather than
    // emptying the inbox over a network blip.
    final failedPrefixes = {
      for (final source in findListSources)
        if (errors.containsKey(_listName[source])) '$source:',
      for (final b in prefs.boards)
        if (errors.containsKey(b.name)) b.keyPrefix,
    };
    for (final p in postings) {
      if (failedPrefixes.any(p.key.startsWith)) byKey.putIfAbsent(p.key, () => p);
    }

    // Keep what earlier description reads found: the feeds don't carry it.
    final prev = {for (final p in postings) p.key: p};
    for (final p in byKey.values) {
      final old = prev[p.key];
      if (old != null && old.sponsorChecked && !p.sponsorChecked) {
        p.sponsor = stricterSponsor(p.sponsor, old.sponsor);
        p.sponsorChecked = true;
      }
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
    _sourcesSig = _sigOf(prefs);
    loading = false;
    notifyListeners();
    await _save();
    unawaited(checkSponsorship());
  }

  bool _checking = false;

  /// How many matching postings still have an unread description.
  int pendingChecks = 0;

  /// Read the descriptions of postings that match your filters (and haven't
  /// been read) for what they say about sponsorship — in the background, a
  /// few at a time, so the inbox shows first and the flags fill in.
  Future<void> checkSponsorship({int max = 250}) async {
    if (_checking) return;
    _checking = true;
    try {
      // Which postings to read: those your other filters keep (the
      // no-sponsorship filter itself needs the answer, so it's ignored here).
      final prefs = FindPrefs.fromJson(store.findPrefs.toJson())..hideNoSponsor = false;
      final todo = postings
          .where((p) => !p.sponsorChecked && descriptionSource(p) != null && findMatches(p, prefs))
          .take(max)
          .toList();
      pendingChecks = todo.length;
      if (todo.isEmpty) return;
      notifyListeners();
      // One download per Ashby board, shared by its postings.
      final boards = <String, Future<dynamic>>{};
      var sinceRepaint = 0;
      Future<void> read(Posting p) async {
        final src = descriptionSource(p)!;
        try {
          final json = src.ats == 'ashby'
              ? await boards.putIfAbsent(src.url, () => _getJson(src.url))
              : await _getJson(src.url);
          final text = descriptionFrom(src.ats, json, id: src.id);
          if (text != null) p.sponsor = stricterSponsor(p.sponsor, scanSponsorship(text));
          p.sponsorChecked = true; // read (or the job page had no description)
        } catch (_) {
          // offline, or the job was taken down: try again next time
        }
        pendingChecks--;
        if (++sinceRepaint >= 8) {
          sinceRepaint = 0;
          notifyListeners();
        }
      }

      final queue = todo.reversed.toList(); // removeLast takes them in order
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          await read(queue.removeLast());
        }
      }

      await Future.wait([for (var i = 0; i < 6; i++) worker()]);
      await _save();
    } finally {
      _checking = false;
      pendingChecks = 0;
      notifyListeners();
    }
  }

  /// Check a careers link before following it: the board, with its name if
  /// the feed says, or an error message.
  static Future<(FollowedBoard?, String?)> resolve(String link, {String? name}) async {
    final b = FollowedBoard.fromLink(link, name: name);
    if (b == null) {
      return (
        null,
        'Find can follow Greenhouse, Lever, Ashby, SmartRecruiters and Workable job boards — '
            'paste a link like boards.greenhouse.io/riotgames, jobs.lever.co/larian, '
            'jobs.ashbyhq.com/hoyoverse, jobs.smartrecruiters.com/Ubisoft2 or apply.workable.com/rovio.'
      );
    }
    try {
      final r = await http.get(Uri.parse(b.feedUrl)).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return (null, 'That board didn\'t answer (HTTP ${r.statusCode}).');
      var title = name;
      if (title == null) {
        // The company's name, where the feed says it.
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map) {
          final first = ((j['jobs'] ?? j['content']) as List?)?.firstOrNull;
          title = switch (b.ats) {
            'greenhouse' => (first as Map?)?['company_name'] as String?,
            'smartrecruiters' => ((first as Map?)?['company'] as Map?)?['name'] as String?,
            'workable' => j['name'] as String?,
            _ => null,
          };
        }
      }
      return (FollowedBoard(b.ats, b.slug, title ?? b.slug), null);
    } catch (e) {
      return (null, 'Couldn\'t reach that board: $e');
    }
  }
}
