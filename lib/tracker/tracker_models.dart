// Internship applications and career/hackathon events — the "Career" section.
// Field names follow the plan's CSV columns exactly, so an export opens in
// Excel with the headers you'd expect and can be imported back.
import 'dart:math';

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

/// Where an item came from. Anything without one is yours (added by hand) —
/// that's every item made before this existed. 'cadence' is for the app's own
/// suggestions and 'email' for the email digester; both are reserved for those
/// features.
const origins = ['you', 'cadence', 'import', 'email'];
const originLabel = {
  'you': 'Added by you',
  'cadence': 'Suggested by Cadence',
  'import': 'Imported',
  'email': 'From email',
};

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
  String? origin; // see [origins]; null = added by you
  int uAt; // per-item sync clock, like Task.uAt

  String get from => origin ?? 'you';

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
    this.origin,
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
        'origin': origin,
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
        origin: _pickOrNull(j['origin'], origins),
        uAt: (j['u'] as num?)?.toInt() ?? 0,
      );

  static const csvColumns = [
    'id', 'company', 'role', 'track', 'term', 'location', 'link', 'source',
    'sponsorship', 'grad_req', 'cv_version', 'status', 'date_applied',
    'deadline', 'contact', 'next_action', 'next_action_date', 'notes', 'origin',
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
  String? origin; // see [origins]; null = added by you
  int uAt;

  String get from => origin ?? 'you';

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
    this.origin,
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
        'origin': origin,
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
        origin: _pickOrNull(j['origin'], origins),
        uAt: (j['u'] as num?)?.toInt() ?? 0,
      );

  static const csvColumns = [
    'id', 'name', 'type', 'start', 'end', 'location', 'link', 'signup_opens',
    'signup_closes', 'status', 'prep', 'outcome', 'related_company', 'origin',
  ];
}

/// [url] as an http(s) link, adding https:// to a bare "riotgames.com/jobs";
/// null for anything else (javascript:, data:, file:, …). Links reach the app
/// from forms, CSV imports and later emails, so only web links are opened.
String? safeWebLink(String url) {
  final t = url.trim();
  var u = Uri.tryParse(t);
  if (u != null && !u.hasScheme) u = Uri.tryParse('https://$t');
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) return null;
  return u.toString();
}

String _pick(dynamic v, List<String> allowed, String fallback) =>
    _pickOrNull(v, allowed) ?? fallback;

String? _pickOrNull(dynamic v, List<String> allowed) {
  final t = _s(v)?.toLowerCase();
  return (t != null && allowed.contains(t)) ? t : null;
}

// ---- goals ----

/// What a goal counts. 'manual' is a counter you bump yourself; the rest are
/// counted from your applications and events, from [Goal.since] on.
const goalMetrics = ['manual', 'applied', 'interviews', 'attended', 'hackathons'];
const goalMetricLabel = {
  'manual': 'I count it myself',
  'applied': 'Applications sent',
  'interviews': 'Interviews reached',
  'attended': 'Events attended',
  'hackathons': 'Hackathons & game jams attended',
};

class Goal {
  int id;
  String title;
  int target;
  String metric;
  int count; // the manual counter (ignored by counted metrics)
  String? since; // yyyy-mm-dd: count from here; null = all time
  String? due; // yyyy-mm-dd: hit the target by then; null = no date
  int uAt;

  Goal({
    required this.id,
    required this.title,
    this.target = 1,
    this.metric = 'manual',
    this.count = 0,
    this.since,
    this.due,
    this.uAt = 0,
  });

  /// Progress toward [target], from the counter or from the records.
  int progress(List<Application> apps, List<TrackEvent> events) {
    final from = parseWhen(since);
    bool after(String? d) {
      if (from == null) return true;
      final x = parseWhen(d);
      return x != null && !x.isBefore(from);
    }

    return switch (metric) {
      'applied' => apps.where((a) => a.status != 'to-apply' && after(a.dateApplied)).length,
      'interviews' => apps
          .where((a) => const {'interview', 'final-round', 'offer'}.contains(a.status))
          .where((a) => after(a.dateApplied))
          .length,
      'attended' => events.where((e) => e.status == 'attended' && after(e.start)).length,
      'hackathons' => events
          .where((e) =>
              e.status == 'attended' &&
              (e.type == 'hackathon' || e.type == 'game-jam') &&
              after(e.start))
          .length,
      _ => count,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'target': target,
        'metric': metric,
        'count': count,
        'since': since,
        'due': due,
        'u': uAt,
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: _s(j['title']) ?? '',
        target: max(1, (j['target'] as num?)?.toInt() ?? 1),
        metric: _pick(j['metric'], goalMetrics, 'manual'),
        count: (j['count'] as num?)?.toInt() ?? 0,
        since: _dateOrNull(j['since']),
        due: _dateOrNull(j['due']),
        uAt: (j['u'] as num?)?.toInt() ?? 0,
      );
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

  /// [urgent] trimmed for the compact DUE SOON banner: one sign-up item per
  /// event (the next one — "opens" before "closes", as [urgent] is in time
  /// order), and none once you're signed up. The Career page keeps the full
  /// list.
  List<AgendaItem> get urgentCompact {
    final seen = <TrackEvent>{};
    return [
      for (final u in urgent)
        if (u.event == null || !u.detail.startsWith('sign-up')) u
        else if (u.event!.status != 'signed-up' && seen.add(u.event!)) u,
    ];
  }

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

/// Everything coming up, however far out — the Career overview's schedule, so
/// longer-term plans are visible, not just the next 48 hours.
class CareerSchedule {
  final List<AgendaItem> running; // events happening right now
  final List<AgendaItem> upcoming; // from now on, soonest first
  final List<TrackEvent> tbd; // events with no date yet

  CareerSchedule._(this.running, this.upcoming, this.tbd);

  /// The next thing on the calendar, if any.
  AgendaItem? get next => upcoming.isEmpty ? null : upcoming.first;

  factory CareerSchedule.build(List<Application> apps, List<TrackEvent> events,
      {DateTime? now}) {
    final n = now ?? DateTime.now();
    bool ahead(DateTime? d) => d != null && !d.isBefore(n);
    final running = <AgendaItem>[], upcoming = <AgendaItem>[], tbd = <TrackEvent>[];

    for (final e in events) {
      if (e.status == 'skipped' || e.status == 'missed') continue;
      final start = e.startAt;
      if (start == null) {
        tbd.add(e);
      } else if (e.type == 'deadline') {
        final due = parseWhen(e.start, endOfDay: true)!;
        if (ahead(due)) upcoming.add(AgendaItem(due, e.name, 'deadline', event: e));
      } else if (ahead(start)) {
        upcoming.add(AgendaItem(start, e.name, e.type, event: e));
      } else if (e.endAt?.isAfter(n) ?? false) {
        running.add(AgendaItem(start, e.name, e.type, event: e));
      }
      // The sign-up window's next moment, while it still needs you.
      if (e.status == 'interested') {
        final opens = parseWhen(e.signupOpens);
        final closes = parseWhen(e.signupCloses, endOfDay: true);
        if (ahead(opens)) {
          upcoming.add(AgendaItem(opens!, e.name, 'sign-up opens', event: e));
        } else if (ahead(closes)) {
          upcoming.add(AgendaItem(closes!, e.name, 'sign-up closes', event: e));
        }
      }
    }

    for (final a in apps) {
      if (a.isClosed) continue;
      final title = a.role.isEmpty ? a.company : '${a.company} — ${a.role}';
      final dl = parseWhen(a.deadline, endOfDay: true);
      if (a.status == 'to-apply' && ahead(dl)) {
        upcoming.add(AgendaItem(dl!, title, 'application closes', app: a));
      }
      final next = parseWhen(a.nextActionDate, endOfDay: true);
      if (ahead(next)) {
        upcoming.add(AgendaItem(next!, title, a.nextAction ?? 'next step', app: a));
      }
    }

    running.sort((a, b) => a.when.compareTo(b.when));
    upcoming.sort((a, b) => a.when.compareTo(b.when));
    return CareerSchedule._(running, upcoming, tbd);
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
