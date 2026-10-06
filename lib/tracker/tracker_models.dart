// Internship applications and career/hackathon events — the "Career" section.
// Field names follow the plan's CSV columns exactly, so an export opens in
// Excel with the headers you'd expect and can be imported back.

// ---- enumerations (stored as their plain strings) ----

const appTracks = ['game', 'swe', 'ai/ml', 'early-program', 'other'];
const appSources = [
  'simplify', 'handshake', 'career-fair', 'company-site', 'referral', 'recruiter', 'other'
];
const sponsorships = ['cpt-ok', 'no-sponsorship', 'unclear'];
const cvVersions = ['general', 'gaming'];

/// The pipeline, in order. The last four are outcomes.
const appStatuses = [
  'to-apply', 'applied', 'oa', 'interview', 'final-round',
  'offer', 'rejected', 'ghosted', 'withdrawn',
];
const appStatusLabel = {
  'to-apply': 'To apply',
  'applied': 'Applied',
  'oa': 'OA',
  'interview': 'Interview',
  'final-round': 'Final round',
  'offer': 'Offer',
  'rejected': 'Rejected',
  'ghosted': 'Ghosted',
  'withdrawn': 'Withdrawn',
};
const _closedStatuses = {'offer', 'rejected', 'ghosted', 'withdrawn'};

/// Statuses that mean the company answered (for the response rate).
const _respondedStatuses = {'oa', 'interview', 'final-round', 'offer', 'rejected'};

const eventTypes = [
  'career-fair', 'company-event', 'hackathon', 'game-jam', 'coaching',
  'info-session', 'deadline', 'social', 'other',
];
const eventStatuses = ['interested', 'signed-up', 'attended', 'skipped', 'missed'];

/// No response this long after applying suggests "ghosted".
const ghostAfter = Duration(days: 42);

/// Weekly application target from the plan.
const weeklyTargetMin = 5;
const weeklyTargetMax = 10;

// ---- dates ----

/// Parses "2026-10-09" or "2026-10-09 12:00" (a "T" also works). A date with no
/// time is read as the start of that day, or its last minute when [endOfDay]
/// — so a deadline of "2026-11-06" isn't past until that day is over.
DateTime? parseWhen(String? s, {bool endOfDay = false}) {
  if (s == null) return null;
  final m = RegExp(r'^\s*(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?')
      .firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (m[4] != null) return DateTime(y, mo, d, int.parse(m[4]!), int.parse(m[5]!));
  return endOfDay ? DateTime(y, mo, d, 23, 59) : DateTime(y, mo, d);
}

bool hasTime(String? s) => s != null && RegExp(r'\d{1,2}:\d{2}').hasMatch(s);

String _two(int n) => n.toString().padLeft(2, '0');
String isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String isoDateTime(DateTime d) => '${isoDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday 00:00 of [d]'s week.
DateTime weekStart(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

String? _s(dynamic v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty) ? null : t;
}

// ---- records ----

class Application {
  int id;
  String company;
  String role;
  String track;
  String? term;
  String? location;
  String? link;
  String source;
  String sponsorship;
  String? gradReq;
  String cvVersion;
  String status;
  String? dateApplied; // yyyy-mm-dd
  String? deadline; // yyyy-mm-dd
  String? contact;
  String? nextAction;
  String? nextActionDate; // yyyy-mm-dd
  String? notes;
  int uAt; // per-item sync clock, like Task.uAt

  Application({
    required this.id,
    required this.company,
    this.role = '',
    this.track = 'swe',
    this.term,
    this.location,
    this.link,
    this.source = 'other',
    this.sponsorship = 'unclear',
    this.gradReq,
    this.cvVersion = 'general',
    this.status = 'to-apply',
    this.dateApplied,
    this.deadline,
    this.contact,
    this.nextAction,
    this.nextActionDate,
    this.notes,
    this.uAt = 0,
  });

  bool get isClosed => _closedStatuses.contains(status);

  Map<String, dynamic> toJson() => {
        'id': id,
        'company': company,
        'role': role,
        'track': track,
        'term': term,
        'location': location,
        'link': link,
        'source': source,
        'sponsorship': sponsorship,
        'grad_req': gradReq,
        'cv_version': cvVersion,
        'status': status,
        'date_applied': dateApplied,
        'deadline': deadline,
        'contact': contact,
        'next_action': nextAction,
        'next_action_date': nextActionDate,
        'notes': notes,
        'u': uAt,
      };

  factory Application.fromJson(Map<String, dynamic> j) => Application(
        id: (j['id'] as num?)?.toInt() ?? 0,
        company: _s(j['company']) ?? '',
        role: _s(j['role']) ?? '',
        track: _pick(j['track'], appTracks, 'other'),
        term: _s(j['term']),
        location: _s(j['location']),
        link: _s(j['link']),
        source: _pick(j['source'], appSources, 'other'),
        sponsorship: _pick(j['sponsorship'], sponsorships, 'unclear'),
        gradReq: _s(j['grad_req']),
        cvVersion: _pick(j['cv_version'], cvVersions, 'general'),
        status: _pick(j['status'], appStatuses, 'to-apply'),
        dateApplied: _s(j['date_applied']),
        deadline: _s(j['deadline']),
        contact: _s(j['contact']),
        nextAction: _s(j['next_action']),
        nextActionDate: _s(j['next_action_date']),
        notes: _s(j['notes']),
        uAt: (j['u'] as num?)?.toInt() ?? 0,
      );

  static const csvColumns = [
    'id', 'company', 'role', 'track', 'term', 'location', 'link', 'source',
    'sponsorship', 'grad_req', 'cv_version', 'status', 'date_applied',
    'deadline', 'contact', 'next_action', 'next_action_date', 'notes',
  ];
}

class TrackEvent {
  int id;
  String name;
  String type;
  String? start; // yyyy-mm-dd or yyyy-mm-dd HH:mm; null = TBD
  String? end;
  String? location;
  String? link;
  String? signupOpens;
  String? signupCloses;
  String status;
  String? prep;
  String? outcome;
  String? relatedCompany;
  int uAt;

  TrackEvent({
    required this.id,
    required this.name,
    this.type = 'other',
    this.start,
    this.end,
    this.location,
    this.link,
    this.signupOpens,
    this.signupCloses,
    this.status = 'interested',
    this.prep,
    this.outcome,
    this.relatedCompany,
    this.uAt = 0,
  });

  DateTime? get startAt => parseWhen(start);

  /// When it's over: its end, else the end of its start day.
  DateTime? get endAt => parseWhen(end, endOfDay: true) ?? parseWhen(start, endOfDay: true);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'start': start,
        'end': end,
        'location': location,
        'link': link,
        'signup_opens': signupOpens,
        'signup_closes': signupCloses,
        'status': status,
        'prep': prep,
        'outcome': outcome,
        'related_company': relatedCompany,
        'u': uAt,
      };

  factory TrackEvent.fromJson(Map<String, dynamic> j) => TrackEvent(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: _s(j['name']) ?? '',
        type: _pick(j['type'], eventTypes, 'other'),
        // "TBD" in a spreadsheet means no date yet.
        start: _dateOrNull(j['start']),
        end: _dateOrNull(j['end']),
        location: _s(j['location']),
        link: _s(j['link']),
        signupOpens: _dateOrNull(j['signup_opens']),
        signupCloses: _dateOrNull(j['signup_closes']),
        status: _pick(j['status'], eventStatuses, 'interested'),
        prep: _s(j['prep']),
        outcome: _s(j['outcome']),
        relatedCompany: _s(j['related_company']),
        uAt: (j['u'] as num?)?.toInt() ?? 0,
      );

  static const csvColumns = [
    'id', 'name', 'type', 'start', 'end', 'location', 'link', 'signup_opens',
    'signup_closes', 'status', 'prep', 'outcome', 'related_company',
  ];
}

String _pick(dynamic v, List<String> allowed, String fallback) {
  final t = _s(v)?.toLowerCase();
  return (t != null && allowed.contains(t)) ? t : fallback;
}

String? _dateOrNull(dynamic v) {
  final t = _s(v);
  return (t == null || parseWhen(t) == null) ? null : t;
}

// ---- the "what should I do today?" agenda ----

/// One line on the Today screen.
class AgendaItem {
  final DateTime when;
  final String title;
  final String detail;
  final Application? app;
  final TrackEvent? event;
  AgendaItem(this.when, this.title, this.detail, {this.app, this.event});
}

class CareerAgenda {
  final List<AgendaItem> urgent; // sign-up windows + deadlines, next 48h
  final List<Application> followUps; // next_action_date today or earlier
  final List<Application> ghostCandidates; // applied 6+ weeks ago, no word
  final List<AgendaItem> thisWeek; // events + deadlines, next 7 days
  final int appliedThisWeek;

  CareerAgenda._(this.urgent, this.followUps, this.ghostCandidates, this.thisWeek,
      this.appliedThisWeek);

  factory CareerAgenda.build(List<Application> apps, List<TrackEvent> events,
      {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = _day(n);
    final soon = n.add(const Duration(hours: 48));
    final week = n.add(const Duration(days: 7));
    bool within(DateTime? d, DateTime until) =>
        d != null && !d.isBefore(n) && !d.isAfter(until);

    final urgent = <AgendaItem>[];
    final thisWeek = <AgendaItem>[];

    for (final e in events) {
      if (e.status == 'skipped' || e.status == 'missed') continue;
      final opens = parseWhen(e.signupOpens);
      final closes = parseWhen(e.signupCloses, endOfDay: true);
      if (within(opens, soon)) {
        urgent.add(AgendaItem(opens!, e.name, 'sign-up opens', event: e));
      }
      if (within(closes, soon) && e.status != 'signed-up') {
        urgent.add(AgendaItem(closes!, e.name, 'sign-up closes', event: e));
      }
      final start = e.startAt;
      // A deadline marked signed-up/attended is already handled (e.g. "Riot
      // application closes — already applied").
      if (e.type == 'deadline' && e.status == 'interested') {
        final due = parseWhen(e.start, endOfDay: true);
        if (within(due, soon)) urgent.add(AgendaItem(due!, e.name, 'deadline', event: e));
      }
      // This week: anything starting in the next 7 days, or already running.
      final running = start != null && start.isBefore(n) && (e.endAt?.isAfter(n) ?? false);
      if (within(start, week) || running) {
        thisWeek.add(AgendaItem(start!, e.name, e.type, event: e));
      }
    }

    for (final a in apps) {
      if (a.isClosed) continue;
      final dl = parseWhen(a.deadline, endOfDay: true);
      if (a.status == 'to-apply' && within(dl, soon)) {
        urgent.add(AgendaItem(dl!, '${a.company} — ${a.role}', 'application closes', app: a));
      }
      if (within(dl, week) && a.status == 'to-apply') {
        thisWeek.add(AgendaItem(dl!, '${a.company} — ${a.role}', 'application closes', app: a));
      }
    }

    final followUps = [
      for (final a in apps)
        if (!a.isClosed && a.nextActionDate != null)
          if (!(parseWhen(a.nextActionDate)?.isAfter(today) ?? true)) a
    ]..sort((x, y) => x.nextActionDate!.compareTo(y.nextActionDate!));

    final ghostLine = today.subtract(ghostAfter);
    final ghostCandidates = [
      for (final a in apps)
        if (a.status == 'applied')
          if (!(parseWhen(a.dateApplied)?.isAfter(ghostLine) ?? true)) a
    ];

    final ws = weekStart(n);
    final applied = apps.where((a) {
      final d = parseWhen(a.dateApplied);
      return d != null && !d.isBefore(ws) && d.isBefore(ws.add(const Duration(days: 7)));
    }).length;

    urgent.sort((a, b) => a.when.compareTo(b.when));
    thisWeek.sort((a, b) => a.when.compareTo(b.when));
    return CareerAgenda._(urgent, followUps, ghostCandidates, thisWeek, applied);
  }
}

// ---- application stats ----

class AppStats {
  final Map<String, int> byStatus;
  final int sent; // everything past "to-apply"
  final int responded;
  AppStats(this.byStatus, this.sent, this.responded);

  /// Share of sent applications that got any answer (OA onwards, or a
  /// rejection). Null until something's been sent.
  double? get responseRate => sent == 0 ? null : responded / sent;

  factory AppStats.of(List<Application> apps) {
    final by = {for (final s in appStatuses) s: 0};
    var sent = 0, responded = 0;
    for (final a in apps) {
      by[a.status] = (by[a.status] ?? 0) + 1;
      if (a.status != 'to-apply') sent++;
      if (_respondedStatuses.contains(a.status)) responded++;
    }
    return AppStats(by, sent, responded);
  }
}

/// Deadline or next action within [days] (and not already past).
bool dueWithin(Application a, int days, {DateTime? now}) {
  if (a.isClosed) return false;
  final n = now ?? DateTime.now();
  final until = _day(n).add(Duration(days: days + 1));
  for (final s in [a.deadline, a.nextActionDate]) {
    final d = parseWhen(s, endOfDay: true);
    if (d != null && !d.isBefore(n) && d.isBefore(until)) return true;
  }
  return false;
}

// ---- the starting list from trackers-plan.md ----

List<Application> starterApplications(int Function() newId) => [
      Application(
          id: newId(), company: 'Riot Games', role: 'Software Engineering Intern',
          track: 'game', term: 'Summer 2027', location: 'Remote (LA)',
          sponsorship: 'no-sponsorship', gradReq: '2028 grads', cvVersion: 'gaming',
          status: 'applied', dateApplied: '2026-10-06', deadline: '2026-11-06',
          notes: 'Product: League of Legends. No sponsorship incl. conversions.'),
      Application(
          id: newId(), company: 'Microsoft', role: 'Explore / SWE Intern',
          track: 'early-program', term: 'Summer 2027', notes: 'Check Explore eligibility'),
      Application(
          id: newId(), company: 'Google', role: 'STEP / SWE Intern',
          track: 'early-program', term: 'Summer 2027', notes: 'Check STEP eligibility'),
      Application(
          id: newId(), company: 'Amazon', role: 'Propel / SWE Intern',
          track: 'early-program', term: 'Summer 2027',
          notes: 'Top target. Spoke to recruiter at fair re: Solutions Architect (Gaming).'),
      Application(
          id: newId(), company: 'Epic Games', role: 'Intern (TBD)',
          track: 'game', term: 'Summer 2027', cvVersion: 'gaming',
          notes: 'Ask lead recruiter in coaching session about grad year + F-1'),
    ];

List<TrackEvent> starterEvents(int Function() newId) => [
      TrackEvent(
          id: newId(), name: 'Virtual Engineering Career Fair', type: 'career-fair',
          start: '2026-10-09 12:00', end: '2026-10-09 17:00',
          location: 'Online (Career Fair Plus)',
          signupOpens: '2026-10-08 12:00', signupCloses: '2026-10-09 12:00',
          prep: 'Sign-up window for non-engineering students is 24h. Check employer '
              'list Thu; apply to top picks first; book 1-on-1s fast.'),
      TrackEvent(
          id: newId(), name: 'MLH Global Hack Week: Hacktoberfest', type: 'hackathon',
          start: '2026-10-09', end: '2026-10-15', location: 'Online'),
      TrackEvent(
          id: newId(), name: 'Game Off 2026', type: 'game-jam',
          start: '2026-11-01', end: '2026-11-30', location: 'Online (itch.io)',
          prep: 'Any engine allowed'),
      TrackEvent(
          id: newId(), name: 'HackRPI 2026', type: 'hackathon',
          start: '2026-11-07', end: '2026-11-08', location: 'Troy, NY',
          prep: 'In person, travel needed'),
      TrackEvent(
          id: newId(), name: 'Epic Games recruiter coaching session', type: 'coaching',
          prep: 'Book when email arrives. Ask: intern timing, grad-year rules, '
              'F-1/CPT, what would make an application stand out.',
          relatedCompany: 'Epic Games'),
      TrackEvent(
          id: newId(), name: 'SpartaHack 12', type: 'hackathon',
          start: '2027-02-06', end: '2027-02-07', location: 'MSU, East Lansing',
          prep: 'Closest next in-person hackathon'),
      TrackEvent(
          id: newId(), name: 'Riot application closes', type: 'deadline',
          start: '2026-11-06', status: 'signed-up', prep: 'Already applied',
          relatedCompany: 'Riot Games'),
    ];
