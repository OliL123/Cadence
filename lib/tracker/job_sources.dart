// Find: job postings pulled from public sources into an inbox, ranked for you.
//
// Sources, all readable straight from the browser (they allow cross-origin
// requests), so no server is involved:
//  * SimplifyJobs' internship list on GitHub — thousands of US/Canada/UK
//    roles with posting dates and an open/closed flag. It has next to nothing
//    in Asia and few game studios, so…
//  * …companies you follow, read from their own job boards (Greenhouse,
//    Lever, Ashby): game studios and Asia offices, with exact posting dates.
//
// This file is the pure part — shapes, parsing, classification, ranking —
// so it's testable without a network. Fetching lives in job_fetch.dart.

import 'tracker_models.dart';

/// One job posting from any source.
class Posting {
  /// Stable id across refreshes: `simplify:<id>`, `gh:<board>:<id>`,
  /// `lever:<board>:<id>`, `ashby:<board>:<id>`.
  final String key;
  final String source; // 'simplify' | 'greenhouse' | 'lever' | 'ashby'
  final String company;
  final String title;
  final List<String> locations;
  final Set<String> countries; // codes from [findCountries]
  final String url;
  final DateTime? posted;
  final String? deadline; // yyyy-mm-dd, when the board gives one
  final String? category; // Simplify's: Software, AI/ML/Data, Quant, …
  final bool gameStudio; // from a followed board marked as a game studio

  Posting({
    required this.key,
    required this.source,
    required this.company,
    required this.title,
    required this.locations,
    required this.url,
    this.posted,
    this.deadline,
    this.category,
    this.gameStudio = false,
    Set<String>? countries,
  }) : countries = countries ?? countriesOf(locations);

  Map<String, dynamic> toJson() => {
        'k': key,
        's': source,
        'c': company,
        't': title,
        'l': locations,
        'n': countries.toList(),
        'u': url,
        if (posted != null) 'p': posted!.millisecondsSinceEpoch,
        if (deadline != null) 'd': deadline,
        if (category != null) 'g': category,
        if (gameStudio) 'gs': true,
      };

  factory Posting.fromJson(Map<String, dynamic> j) => Posting(
        key: j['k'] as String,
        source: j['s'] as String,
        company: j['c'] as String,
        title: j['t'] as String,
        locations: (j['l'] as List).cast<String>(),
        countries: (j['n'] as List?)?.cast<String>().toSet(),
        url: j['u'] as String,
        posted: j['p'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['p'] as int),
        deadline: j['d'] as String?,
        category: j['g'] as String?,
        gameStudio: j['gs'] == true,
      );
}

// ---------------------------------------------------------------- countries

/// Countries Find can filter on, in chip order.
const findCountries = [
  'US', 'HK', 'MY', 'SG', 'CN', 'AU', 'CA', 'UK', 'TW', 'JP', 'KR', 'EU', 'REMOTE',
];
const findCountryLabel = {
  'US': 'United States',
  'HK': 'Hong Kong',
  'MY': 'Malaysia',
  'SG': 'Singapore',
  'CN': 'China',
  'AU': 'Australia',
  'CA': 'Canada',
  'UK': 'United Kingdom',
  'TW': 'Taiwan',
  'JP': 'Japan',
  'KR': 'Korea',
  'EU': 'Europe',
  'REMOTE': 'Remote (anywhere)',
  'OTHER': 'Elsewhere',
};

const _usStates = {
  'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID', 'IL',
  'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS', 'MO', 'MT',
  'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI',
  'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY', 'DC', 'PR',
};
const _usStateNames = {
  'alabama', 'alaska', 'arizona', 'arkansas', 'california', 'colorado',
  'connecticut', 'delaware', 'florida', 'georgia', 'hawaii', 'idaho',
  'illinois', 'indiana', 'iowa', 'kansas', 'kentucky', 'louisiana', 'maine',
  'maryland', 'massachusetts', 'michigan', 'minnesota', 'mississippi',
  'missouri', 'montana', 'nebraska', 'nevada', 'new hampshire', 'new jersey',
  'new mexico', 'new york', 'north carolina', 'north dakota', 'ohio',
  'oklahoma', 'oregon', 'pennsylvania', 'rhode island', 'south carolina',
  'south dakota', 'tennessee', 'texas', 'utah', 'vermont', 'virginia',
  'washington', 'west virginia', 'wisconsin', 'wyoming',
};

final _cc = <String, RegExp>{
  'HK': RegExp(r'hong kong|\bhk\b|kowloon', caseSensitive: false),
  'SG': RegExp(r'singapore', caseSensitive: false),
  'MY': RegExp(r'malaysia|kuala lumpur|penang|cyberjaya|johor', caseSensitive: false),
  'TW': RegExp(r'taiwan|taipei|hsinchu|taichung', caseSensitive: false),
  'CN': RegExp(
      r'china|shanghai|beijing|shenzhen|hangzhou|guangzhou|chengdu|nanjing|suzhou|wuhan|xiamen',
      caseSensitive: false),
  'JP': RegExp(r'japan|tokyo|osaka|kyoto|fukuoka', caseSensitive: false),
  'KR': RegExp(r'korea|seoul|pangyo|busan|seongnam', caseSensitive: false),
  // "Melbourne, FL" is Florida.
  'AU': RegExp(r'australia|sydney|brisbane|perth|canberra|adelaide|\bnsw\b|melbourne(?!,\s*fl)',
      caseSensitive: false),
  // Before UK: "London, ON" is Canada.
  'CA': RegExp(
      r'canada|,\s*(on|bc|qc|ab|mb|sk|ns|nb|nl|pe)\b|toronto|vancouver|montr[eé]al|waterloo|ottawa|calgary',
      caseSensitive: false),
  'UK': RegExp(r'\buk\b|united kingdom|england|scotland|wales|london|manchester|edinburgh|cambridge, uk',
      caseSensitive: false),
  'EU': RegExp(
      r'germany|berlin|munich|ireland|dublin|france|paris|netherlands|amsterdam|spain|madrid|barcelona|'
      r'poland|warsaw|sweden|stockholm|finland|helsinki|denmark|copenhagen|portugal|lisbon|porto|'
      r'italy|milan|switzerland|zurich|belgium|austria|vienna, austria|czech|prague|serbia|romania|'
      r'bucharest|hungary|budapest|norway|oslo',
      caseSensitive: false),
  'US': RegExp(r'united states|\busa\b|^nyc$|^sf$|^la$|south sf|bay area|new york|silicon valley',
      caseSensitive: false),
};

/// The country of one location string, as written by any of the sources
/// ("San Jose, CA", "Shanghai, China", "Cary,North Carolina,United States",
/// "Remote in USA", "Singapore").
String countryOf(String location) {
  final l = location.trim();
  for (final e in _cc.entries) {
    if (e.value.hasMatch(l)) return e.key;
  }
  final st = RegExp(r',\s*([A-Z]{2})\s*$').firstMatch(l);
  if (st != null && _usStates.contains(st[1])) return 'US';
  if (_usStateNames.contains(l.toLowerCase())) return 'US';
  if (RegExp(r'remote', caseSensitive: false).hasMatch(l)) return 'REMOTE';
  return 'OTHER';
}

Set<String> countriesOf(List<String> locations) =>
    locations.isEmpty ? {'OTHER'} : {for (final l in locations) countryOf(l)};

/// ISO country codes some boards give directly (Lever's "country").
const _isoToFind = {
  'US': 'US', 'HK': 'HK', 'MY': 'MY', 'SG': 'SG', 'CN': 'CN', 'AU': 'AU',
  'CA': 'CA', 'GB': 'UK', 'TW': 'TW', 'JP': 'JP', 'KR': 'KR',
};

// ---------------------------------------------------------------- interests

/// What kind of role, for the interest chips and the ranking.
const findInterests = ['game', 'swe', 'ml', 'data', 'quant', 'hardware', 'product'];
const findInterestLabel = {
  'game': 'Game dev',
  'swe': 'Software',
  'ml': 'ML / AI',
  'data': 'Data',
  'quant': 'Quant / finance',
  'hardware': 'Hardware',
  'product': 'Product / design',
};

final _gameRe = RegExp(
    r'\bgames?\b|gameplay|\bgraphics\b|\bunreal\b|\bunity\b|\brendering\b|engine programmer|'
    r'game engine|game design|technical art|tech art|level design|\bxr\b|\bvr\b|\bar/vr\b|animation programmer',
    caseSensitive: false);

/// Studios whose every role counts as game dev.
final _gameCompanies = RegExp(
    r'riot|epic games|roblox|bungie|blizzard|activision|electronic arts|\bea\b|ubisoft|valve|'
    r'nintendo|playstation|sony interactive|naughty dog|insomniac|bethesda|zenimax|rockstar|'
    r'\b2k\b|take-two|gearbox|respawn|supercell|scopely|zynga|niantic|kabam|jam city|larian|'
    r'hoyoverse|mihoyo|krafton|nexon|netease games|tencent games|garena|moonton|lilith|'
    r'bandai namco|square enix|capcom|sega|cd projekt|wargaming|jagex|rovio|unity technologies|'
    r'mojang|playtika|pocket gems|wizards of the coast|digital extremes|bioware|treyarch|'
    r'infinity ward|sucker punch|santa monica studio|bungie',
    caseSensitive: false);

final _financeCompany = RegExp(
    r'\bbank|capital\b|securities|financial|finance|\btrading|asset management|investment|'
    r'insurance|credit union|\bfund\b|jpmorgan|j\.p\. morgan|goldman|morgan stanley|citi(group|bank)?\b|'
    r'wells fargo|barclays|hsbc|blackrock|fidelity|vanguard|jane street|citadel|two sigma|'
    r'hudson river|optiver|\bimc\b|susquehanna|d\.? ?e\.? shaw|state street|capital one|'
    r'american express|charles schwab|nasdaq|\bcme\b|federal reserve|federal home loan',
    caseSensitive: false);

bool isFinanceCompany(Posting p) => _financeCompany.hasMatch(p.company);

/// The interests a posting matches; 'other' when none fits (communications,
/// people ops, sales…), which no chip selects, so those stay out of Find.
Set<String> interestsOf(Posting p) {
  final t = p.title;
  final cat = (p.category ?? '').toLowerCase();
  final out = <String>{};
  final ml = RegExp(
      r'machine learning|\bml\b|\bai\b|artificial intelligence|deep learning|computer vision|'
      r'\bnlp\b|\bllm|research scientist|applied scientist|generative|reinforcement learning',
      caseSensitive: false);
  if (ml.hasMatch(t)) out.add('ml');
  if (RegExp(r'data scien|data analy|data engineer|analytics|business intelligence',
          caseSensitive: false)
      .hasMatch(t)) {
    out.add('data');
  }
  if (cat.contains('ai/ml') && !out.contains('ml') && !out.contains('data')) out.add('data');
  if (cat.contains('quant') || RegExp(r'quant|trading|trader', caseSensitive: false).hasMatch(t)) {
    out.add('quant');
  }
  if (cat.contains('hardware') ||
      RegExp(r'hardware|electrical|embedded|firmware|asic|fpga|silicon|circuit',
              caseSensitive: false)
          .hasMatch(t)) {
    out.add('hardware');
  }
  if (cat.contains('product') ||
      RegExp(r'product manag|program manag|\bux\b|\bui/ux\b|designer\b', caseSensitive: false)
          .hasMatch(t)) {
    out.add('product');
  }
  if (cat.contains('software') ||
      RegExp(
              r'software|developer|programmer|back-?end|front-?end|full.?stack|mobile|\bios\b|android|'
              r'\bweb\b|devops|\bsre\b|infrastructure|platform|security|cloud|systems? engineer|'
              r'engineering intern|\bswe\b|\bsdet\b|\bqa\b|quality assurance|test engineer|automation',
              caseSensitive: false)
          .hasMatch(t)) {
    out.add('swe');
  }
  // Game dev: a game-craft title anywhere, or a technical role at a studio.
  // (A studio's communications or PM intern isn't game dev.)
  final studio = p.gameStudio || _gameCompanies.hasMatch(p.company);
  if (_gameRe.hasMatch(t) ||
      (studio && out.any(const {'swe', 'ml', 'data', 'hardware'}.contains))) {
    out.add('game');
  }
  if (out.isEmpty) out.add('other');
  return out;
}

/// The Application track an added posting gets.
String trackFor(Posting p) {
  final i = interestsOf(p);
  if (i.contains('game')) return 'game';
  if (i.contains('ml')) return 'ai/ml';
  return 'swe';
}

// ---------------------------------------------------------------- settings

/// A company followed through its job board.
class FollowedBoard {
  final String ats; // 'greenhouse' | 'lever' | 'ashby'
  final String slug; // the board's id in its URL, e.g. "riotgames"
  final String name;
  final bool game; // a game studio: all its roles count as game dev

  const FollowedBoard(this.ats, this.slug, this.name, {this.game = false});

  String get id => '$ats:$slug';

  Map<String, dynamic> toJson() => {'a': ats, 's': slug, 'n': name, if (game) 'g': true};
  factory FollowedBoard.fromJson(Map<String, dynamic> j) =>
      FollowedBoard(j['a'] as String, j['s'] as String, j['n'] as String, game: j['g'] == true);

  /// The board's public jobs feed (all three allow cross-origin reads).
  String get feedUrl => switch (ats) {
        'greenhouse' => 'https://boards-api.greenhouse.io/v1/boards/$slug/jobs',
        'lever' => 'https://api.lever.co/v0/postings/$slug?mode=json',
        _ => 'https://api.ashbyhq.com/posting-api/job-board/$slug',
      };

  /// A careers link → its board, for the boards Find can read; null for
  /// anything else (Workday, company sites…).
  static FollowedBoard? fromLink(String link, {String? name}) {
    final m = RegExp(
            r'(?:boards|job-boards)(?:\.eu)?\.greenhouse\.io/(?:embed/job_board\?for=)?([\w-]+)|'
            r'jobs(?:\.eu)?\.lever\.co/([\w-]+)|jobs\.ashbyhq\.com/([\w%.-]+)',
            caseSensitive: false)
        .firstMatch(link);
    if (m == null) return null;
    final ats = m[1] != null ? 'greenhouse' : m[2] != null ? 'lever' : 'ashby';
    final slug = (m[1] ?? m[2] ?? m[3])!;
    return FollowedBoard(ats, slug, name ?? slug);
  }
}

/// Boards checked to exist and be readable (Oct 2026): game studios first,
/// then tech with Asia offices. Offered as one-tap follows.
const suggestedBoards = [
  FollowedBoard('greenhouse', 'riotgames', 'Riot Games', game: true),
  FollowedBoard('greenhouse', 'epicgames', 'Epic Games', game: true),
  FollowedBoard('greenhouse', 'roblox', 'Roblox', game: true),
  FollowedBoard('greenhouse', 'sonyinteractiveentertainmentglobal', 'PlayStation', game: true),
  FollowedBoard('ashby', 'hoyoverse', 'HoYoverse', game: true),
  FollowedBoard('greenhouse', 'krafton', 'Krafton', game: true),
  FollowedBoard('ashby', 'supercell', 'Supercell', game: true),
  FollowedBoard('greenhouse', 'scopely', 'Scopely', game: true),
  FollowedBoard('lever', 'larian', 'Larian Studios', game: true),
  FollowedBoard('greenhouse', '2k', '2K', game: true),
  FollowedBoard('greenhouse', 'naughtydog', 'Naughty Dog', game: true),
  FollowedBoard('greenhouse', 'insomniac', 'Insomniac Games', game: true),
  FollowedBoard('greenhouse', 'nintendo', 'Nintendo of America', game: true),
  FollowedBoard('lever', 'kabam', 'Kabam', game: true),
  FollowedBoard('lever', 'jamcity', 'Jam City', game: true),
  FollowedBoard('greenhouse', 'discord', 'Discord'),
  FollowedBoard('greenhouse', 'twitch', 'Twitch'),
  FollowedBoard('greenhouse', 'agoda', 'Agoda'),
  FollowedBoard('ashby', 'airwallex', 'Airwallex'),
  FollowedBoard('lever', 'lalamove', 'Lalamove'),
  FollowedBoard('ashby', 'xero', 'Xero'),
  FollowedBoard('greenhouse', 'figma', 'Figma'),
  FollowedBoard('greenhouse', 'databricks', 'Databricks'),
  FollowedBoard('greenhouse', 'anthropic', 'Anthropic'),
  FollowedBoard('greenhouse', 'scaleai', 'Scale AI'),
];

/// Find's filters. A setting: it syncs, newest wins.
class FindPrefs {
  String term;
  List<String> countries;
  List<String> interests;
  int maxAgeDays; // 0 = any age
  bool useSimplify;
  bool hideAdvancedDegree; // PhD/MBA-only roles
  List<FollowedBoard> boards;

  FindPrefs({
    this.term = 'Summer 2027',
    List<String>? countries,
    List<String>? interests,
    this.maxAgeDays = 60,
    this.useSimplify = true,
    this.hideAdvancedDegree = true,
    List<FollowedBoard>? boards,
  })  : countries = countries ?? ['US', 'HK', 'MY', 'SG', 'CN', 'AU'],
        interests = interests ?? ['game', 'swe', 'ml'],
        boards = boards ?? suggestedBoards.where((b) => b.game).toList();

  Map<String, dynamic> toJson() => {
        'term': term,
        'countries': countries,
        'interests': interests,
        'maxAge': maxAgeDays,
        'simplify': useSimplify,
        'noAdv': hideAdvancedDegree,
        'boards': boards.map((b) => b.toJson()).toList(),
      };

  factory FindPrefs.fromJson(Map<String, dynamic> j) => FindPrefs(
        term: j['term'] as String? ?? 'Summer 2027',
        countries: (j['countries'] as List?)?.cast<String>(),
        interests: (j['interests'] as List?)?.cast<String>(),
        maxAgeDays: (j['maxAge'] as num?)?.toInt() ?? 60,
        useSimplify: j['simplify'] as bool? ?? true,
        hideAdvancedDegree: j['noAdv'] as bool? ?? true,
        boards: (j['boards'] as List?)
            ?.map((b) => FollowedBoard.fromJson(Map<String, dynamic>.from(b as Map)))
            .toList(),
      );
}

// ---------------------------------------------------------------- parsing

DateTime? _epochS(dynamic v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch((v * 1000).toInt()) : null;

/// SimplifyJobs' listings.json → open, visible postings for [term], plus the
/// keys of every listing it marks closed (to flag ones you already added).
({List<Posting> open, Set<String> closed}) parseSimplify(List<dynamic> raw,
    {String term = 'Summer 2027', bool hideAdvancedDegree = true}) {
  final open = <Posting>[];
  final closed = <String>{};
  for (final r in raw) {
    if (r is! Map) continue;
    final key = 'simplify:${r['id']}';
    if (r['active'] != true || r['is_visible'] != true) {
      closed.add(key);
      continue;
    }
    final terms = (r['terms'] as List?)?.map((e) => '$e').toList() ?? const [];
    if (!terms.contains(term)) continue;
    final degrees = (r['degrees'] as List?)?.map((e) => '$e').toList() ?? const [];
    if (hideAdvancedDegree &&
        degrees.isNotEmpty &&
        !degrees.any((d) => d.startsWith('Bachelor') || d.startsWith('Master') || d.startsWith('Associate'))) {
      continue;
    }
    open.add(Posting(
      key: key,
      source: 'simplify',
      company: '${r['company_name'] ?? ''}'.trim(),
      title: '${r['title'] ?? ''}'.trim(),
      locations: (r['locations'] as List?)?.map((e) => '$e').toList() ?? const [],
      url: '${r['url'] ?? ''}',
      posted: _epochS(r['date_posted']),
      category: r['category'] as String?,
    ));
  }
  return (open: open, closed: closed);
}

final _studentRole = RegExp(
    r'intern\b|internship|co-?op\b|placement|student|trainee|apprentice|实习|實習',
    caseSensitive: false);

/// A board posting is kept if it's a student role and doesn't name a
/// different term ("Summer 2026", "Fall 2027" when looking for Summer 2027).
bool _fitsTerm(String title, String term) {
  final tm = RegExp(r'(spring|summer|fall|autumn|winter)\s*(20\d\d)', caseSensitive: false)
      .firstMatch(title);
  if (tm != null) return '${tm[1]} ${tm[2]}'.toLowerCase() == term.toLowerCase();
  final year = RegExp(r'\b(20\d\d)\b').firstMatch(title);
  final want = RegExp(r'\b(20\d\d)\b').firstMatch(term)?[1];
  return year == null || want == null || year[1] == want;
}

List<Posting> parseBoard(FollowedBoard b, dynamic raw, {String term = 'Summer 2027'}) {
  final out = <Posting>[];
  void add(String id, String title, List<String> locs, String url, DateTime? posted,
      {String? deadline, Set<String>? countries, String? commitment}) {
    final student = _studentRole.hasMatch(title) || _studentRole.hasMatch(commitment ?? '');
    if (!student || !_fitsTerm(title, term)) return;
    final c = countries ?? countriesOf(locs);
    out.add(Posting(
      key: '${b.ats == 'greenhouse' ? 'gh' : b.ats}:${b.slug}:$id',
      source: b.ats,
      company: b.name,
      title: title.trim(),
      locations: locs,
      countries: c.isEmpty ? {'OTHER'} : c,
      url: url,
      posted: posted,
      deadline: deadline,
      gameStudio: b.game,
    ));
  }

  switch (b.ats) {
    case 'greenhouse':
      for (final j in ((raw as Map)['jobs'] as List? ?? const [])) {
        final loc = '${(j['location'] as Map?)?['name'] ?? ''}';
        add(
          '${j['id']}',
          '${j['title']}',
          loc.split(RegExp(r';|\s\|\s')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          '${j['absolute_url']}',
          DateTime.tryParse('${j['first_published'] ?? j['updated_at'] ?? ''}'),
          deadline: (j['application_deadline'] as String?)?.split('T').first,
        );
      }
    case 'lever':
      for (final j in (raw as List? ?? const [])) {
        final cat = (j['categories'] as Map?) ?? const {};
        final locs = ((cat['allLocations'] as List?) ?? [cat['location']])
            .whereType<String>()
            .toList();
        final iso = _isoToFind[j['country']];
        add(
          '${j['id']}',
          '${j['text']}',
          locs,
          '${j['hostedUrl']}',
          j['createdAt'] is num ? DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt()) : null,
          countries: {?iso, ...countriesOf(locs)}..remove(iso == null ? '' : 'OTHER'),
          commitment: cat['commitment'] as String?,
        );
      }
    case 'ashby':
      for (final j in ((raw as Map)['jobs'] as List? ?? const [])) {
        if (j['isListed'] == false) continue;
        final locs = <String>[
          if (j['location'] != null) '${j['location']}',
          for (final s in (j['secondaryLocations'] as List? ?? const []))
            if (s is Map && s['location'] != null) '${s['location']}',
        ];
        final addr = (((j['address'] as Map?)?['postalAddress']) as Map?)?['addressCountry'];
        add(
          '${j['id']}',
          '${j['title']}',
          locs,
          '${j['jobUrl']}',
          DateTime.tryParse('${j['publishedAt'] ?? ''}'),
          countries: {...countriesOf(locs), if (addr != null) countryOf('$addr')}
            ..remove(locs.isEmpty && addr == null ? '' : 'OTHER'),
          commitment: j['employmentType'] as String?,
        );
      }
  }
  return out;
}

// ---------------------------------------------------------------- ranking

/// What your choices say you like: words from roles you added, applied to
/// or marked important count up; words from postings you dismissed count
/// down. Plain word overlap on titles — no model, works offline.
class FindTaste {
  final Map<String, double> _w;
  final Set<String> likedCompanies;
  final Map<String, int> dismissedCompanies;
  FindTaste._(this._w, this.likedCompanies, this.dismissedCompanies);

  static const _stop = {
    'intern', 'internship', 'summer', 'fall', 'spring', 'winter', 'the', 'and', 'for', 'with',
    'of', 'in', 'to', 'a', 'an', 'co', 'op', 'program', 'student', 'university', 'team',
    '2026', '2027', '2028', 'usa', 'us', 'remote', 'hybrid',
  };

  static Set<String> words(String title) => title
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9+#]+'))
      .where((w) => w.length >= 2 && !_stop.contains(w))
      .toSet();

  factory FindTaste.from({
    required Iterable<Application> liked,
    required Iterable<String> dismissed, // "company — title"
    Iterable<String> pinned = const [],
  }) {
    final pos = <String, int>{}, neg = <String, int>{};
    var nPos = 0, nNeg = 0;
    final likedCo = <String>{...pinned.map((c) => c.toLowerCase().trim())};
    for (final a in liked) {
      nPos++;
      likedCo.add(a.company.toLowerCase().trim());
      for (final w in words(a.role)) {
        pos[w] = (pos[w] ?? 0) + 1;
      }
    }
    final disCo = <String, int>{};
    for (final d in dismissed) {
      nNeg++;
      final parts = d.split(' — ');
      final co = parts.first.toLowerCase().trim();
      disCo[co] = (disCo[co] ?? 0) + 1;
      for (final w in words(parts.length > 1 ? parts.sublist(1).join(' ') : d)) {
        neg[w] = (neg[w] ?? 0) + 1;
      }
    }
    final w = <String, double>{};
    for (final k in {...pos.keys, ...neg.keys}) {
      w[k] = (nPos == 0 ? 0 : (pos[k] ?? 0) / nPos) - 0.6 * (nNeg == 0 ? 0 : (neg[k] ?? 0) / nNeg);
    }
    return FindTaste._(w, likedCo, disCo);
  }

  /// -20 … +30 from the title's words, plus the company's history.
  int bonus(Posting p) {
    final ws = words(p.title);
    var s = 0.0;
    for (final x in ws) {
      s += _w[x] ?? 0;
    }
    var b = ws.isEmpty ? 0 : (s / ws.length * 120).round().clamp(-20, 30);
    final co = p.company.toLowerCase().trim();
    if (likedCompanies.contains(co)) b += 15;
    if ((dismissedCompanies[co] ?? 0) >= 3) b -= 10;
    return b;
  }
}

/// How well a posting fits: your interests (in the order you care about
/// them — game first), your countries, how fresh it is, a deadline coming
/// up, a company you follow, and your taste. Finance sinks unless you
/// asked for quant/finance.
int findScore(Posting p, FindPrefs prefs, FindTaste taste, {DateTime? now}) {
  final n = now ?? DateTime.now();
  var s = 0;
  final ints = interestsOf(p);
  const weight = {'game': 30, 'swe': 18, 'ml': 14, 'data': 8, 'quant': 6, 'hardware': 6, 'product': 6};
  var best = 0;
  for (final i in ints) {
    if (prefs.interests.contains(i) && (weight[i] ?? 0) > best) best = weight[i]!;
  }
  s += best;
  if (p.countries.any(prefs.countries.contains)) s += 10;
  if (p.posted != null) {
    final days = n.difference(p.posted!).inHours / 24;
    s += days <= 3
        ? 25
        : days <= 7
            ? 18
            : days <= 14
                ? 12
                : days <= 30
                    ? 6
                    : days <= 60
                        ? 2
                        : 0;
  }
  final dl = parseWhen(p.deadline, endOfDay: true);
  if (dl != null && dl.isAfter(n) && dl.difference(n).inDays <= 14) s += 20;
  if (p.source != 'simplify') s += 12; // a company you chose to follow
  if (!prefs.interests.contains('quant') && (isFinanceCompany(p) || ints.contains('quant'))) s -= 20;
  return s + taste.bonus(p);
}

/// Whether [p] passes the chips: a chosen country, a chosen interest, and
/// recent enough.
bool findMatches(Posting p, FindPrefs prefs, {DateTime? now}) {
  if (!p.countries.any(prefs.countries.contains)) return false;
  if (!interestsOf(p).any(prefs.interests.contains)) return false;
  if (prefs.maxAgeDays > 0 && p.posted != null) {
    final n = now ?? DateTime.now();
    if (n.difference(p.posted!).inDays > prefs.maxAgeDays) return false;
  }
  return true;
}
