// The Career section: an overview (the whole schedule beside goals and
// metrics), the applications pipeline, and events — built from trackers-plan.md.
import 'package:flutter/material.dart';

import '../palette.dart';
import '../store.dart';
import '../widgets/felt.dart';
import '../widgets/type.dart';
import '../platform/csv_io_stub.dart'
    if (dart.library.js_interop) '../platform/csv_io_web.dart' as csvio;
import 'career_forms.dart';
import 'tracker_csv.dart';
import 'tracker_models.dart';

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmtDay(DateTime d) => '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';

/// "Thu 8 Oct · 12:00", or "Thu 8 Oct" for a date with no time.
String fmtWhen(String? s) {
  final d = parseWhen(s);
  if (d == null) return 'TBD';
  return hasTime(s) ? '${_fmtDay(d)} · ${isoDateTime(d).substring(11)}' : _fmtDay(d);
}

String _fmtRange(TrackEvent e) {
  if (e.start == null) return 'Date TBD';
  if (e.end == null || e.end == e.start) return fmtWhen(e.start);
  final a = parseWhen(e.start)!, b = parseWhen(e.end);
  if (b != null && a.year == b.year && a.month == b.month && a.day == b.day) {
    return '${fmtWhen(e.start)}–${isoDateTime(b).substring(11)}';
  }
  return '${fmtWhen(e.start)} → ${fmtWhen(e.end)}';
}

Color statusColor(String s) => switch (s) {
      'applied' => C.navy,
      'oa' => C.mustard,
      'interview' || 'final-round' => C.teal,
      'offer' => C.green,
      'rejected' => C.red,
      _ => C.ink3,
    };

class CareerPage extends StatefulWidget {
  const CareerPage({super.key});
  @override
  State<CareerPage> createState() => _CareerPageState();
}

class _CareerPageState extends State<CareerPage> {
  String _tab = 'overview'; // overview | apps | events
  String _narrowPane = 'schedule'; // overview on a narrow screen: schedule | goals
  String? _fTrack, _fStatus, _fSponsor;

  /// For the tab widgets, which hold no state of their own.
  void _update(VoidCallback change) => setState(change);

  void _snack(String msg, {VoidCallback? undo}) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: undo == null ? 4 : 8),
      action: undo == null ? null : SnackBarAction(label: 'UNDO', onPressed: undo),
    ));

  /// Companies whose roles are shown open in the Applications board, keyed
  /// "status|company". Everything else with several roles stays one card.
  final Set<String> _openCompanies = {};

  /// One-tap "I applied": moves a to-apply card to Applied, with UNDO.
  void _markApplied(Application a) {
    final was = (a.status, a.dateApplied);
    store.setAppStatus(a, 'applied');
    _snack('${a.company} marked applied',
        undo: () => store.revertAppStatus(a, was.$1, was.$2));
  }

  Future<void> _export(bool apps) async {
    final name = apps ? 'applications.csv' : 'events.csv';
    await csvio.saveTextFile(
        name, apps ? applicationsToCsv(store.applications) : eventsToCsv(store.trackEvents));
    if (!csvio.csvIoUsesFiles) _snack('Copied $name — paste it into a spreadsheet');
  }

  Future<void> _import() async {
    final texts = await csvio.pickTextFiles();
    if (texts.isEmpty) {
      if (!csvio.csvIoUsesFiles) _snack('Copy a CSV first, then tap Import');
      return;
    }
    final msgs = <String>[];
    final addedApps = <int>[], addedEvents = <int>[];
    for (final t in texts) {
      final rows = parseCsv(t);
      switch (csvKind(rows)) {
        case CsvKind.applications:
          final r = store.importApplications(applicationsFromCsv(rows));
          addedApps.addAll(r.ids);
          msgs.add('${r.added} applications added, ${r.updated} updated'
              '${r.skipped > 0 ? ', ${r.skipped} already here' : ''}');
        case CsvKind.events:
          final r = store.importEvents(eventsFromCsv(rows));
          addedEvents.addAll(r.ids);
          msgs.add('${r.added} events added, ${r.updated} updated'
              '${r.skipped > 0 ? ', ${r.skipped} already here' : ''}');
        case CsvKind.unknown:
          msgs.add('one file wasn\'t an applications or events CSV');
      }
    }
    // UNDO takes back exactly the rows this import added.
    _snack(msgs.join(' · '),
        undo: addedApps.isEmpty && addedEvents.isEmpty
            ? null
            : () => store.removeCareerItems(addedApps, addedEvents));
  }

  /// Take back an earlier import: pick it from a list (newest first), remove
  /// the rows it added that haven't been edited since — with UNDO.
  Future<void> _undoImport() async {
    final batches = store.importBatches();
    if (batches.isEmpty) {
      _snack('No imports left to undo');
      return;
    }
    String when(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '${fmtWhen(isoDate(d))}, $h:${d.minute.toString().padLeft(2, '0')}'
          '${d.hour < 12 ? 'am' : 'pm'}';
    }
    String what(({int at, int apps, int events}) b) => [
          if (b.apps > 0) '${b.apps} application${b.apps == 1 ? '' : 's'}',
          if (b.events > 0) '${b.events} event${b.events == 1 ? '' : 's'}',
        ].join(' + ');
    final at = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.paper2,
        title: const Text('Undo an import'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Removes the rows an import added that you haven\'t edited '
                'since. Anything you moved or changed stays.',
                style: TextStyle(fontSize: 13, color: C.ink2)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final b in batches.take(12))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.upload_file, color: C.ink3),
                    title: Text(what(b), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('added ${when(b.at)}'),
                    trailing: const Icon(Icons.undo, color: C.red),
                    onTap: () => Navigator.pop(d, b.at),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        ],
      ),
    );
    if (at == null) return;
    final gone = store.removeImportBatch(at);
    _snack('Removed ${gone.apps.length + gone.events.length} imported items',
        undo: () => store.restoreCareer(gone.apps, gone.events));
  }

  /// Collapse copies into one, after saying how many there are.
  Future<void> _removeDuplicates() async {
    final n = store.countDuplicates();
    if (n.apps + n.events == 0) {
      _snack('No duplicates found');
      return;
    }
    String plural(int k, String w) => '$k $w${k == 1 ? '' : 's'}';
    final what = [
      if (n.apps > 0) plural(n.apps, 'duplicate application'),
      if (n.events > 0) plural(n.events, 'duplicate event'),
    ].join(' and ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: C.paper2,
        title: const Text('Remove duplicates?'),
        content: Text('Found $what. One copy of each is kept — the one '
            'furthest along — and anything filled in only on another copy '
            'is copied onto it first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            style: FilledButton.styleFrom(backgroundColor: C.green),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = store.removeDuplicates();
    _snack('Removed ${r.apps + r.events} duplicate${r.apps + r.events == 1 ? '' : 's'}');
  }

  void _add() {
    switch (_tab) {
      case 'apps':
        showApplicationForm(context);
      case 'events':
        showEventForm(context);
      default:
        showModalBottomSheet(
          context: context,
          backgroundColor: C.paper2,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.work_outline),
                title: const Text('Application'),
                onTap: () {
                  Navigator.pop(ctx);
                  showApplicationForm(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Event'),
                onTap: () {
                  Navigator.pop(ctx);
                  showEventForm(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Goal'),
                onTap: () {
                  Navigator.pop(ctx);
                  showGoalForm(context);
                },
              ),
            ]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: C.paper2,
          border: Border.all(color: C.green, width: 2),
          borderRadius: BorderRadius.circular(9),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          const Divider(height: 1, color: C.line),
          Expanded(
            child: switch (_tab) {
              'apps' => _AppsTab(this),
              'events' => _EventsTab(this),
              _ => _OverviewTab(this),
            },
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    Widget tab(String id, String label) {
      final on = _tab == id;
      return InkWell(
        onTap: () => setState(() => _tab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: on ? C.green : C.paper2,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? C.creamTxt : C.greenD)),
        ),
      );
    }

    final tabs = Container(
      decoration: BoxDecoration(
          border: Border.all(color: C.green, width: 2), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        tab('overview', 'Overview'),
        Container(width: 2, height: 30, color: C.green),
        tab('apps', 'Applications ${store.applications.length}'),
        Container(width: 2, height: 30, color: C.green),
        tab('events', 'Events ${store.trackEvents.length}'),
      ]),
    );
    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      FilledButton.icon(
        onPressed: _add,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add', style: TextStyle(fontSize: 12.5)),
        style: FilledButton.styleFrom(
            backgroundColor: C.mustard,
            foregroundColor: C.ink,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      ),
      PopupMenuButton<String>(
        tooltip: 'CSV',
        icon: const Icon(Icons.more_vert, color: C.ink2),
        onSelected: (v) {
          switch (v) {
            case 'xa':
              _export(true);
            case 'xe':
              _export(false);
            case 'imp':
              _import();
            case 'dup':
              _removeDuplicates();
            case 'undoimp':
              _undoImport();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'xa',
              child: Text(csvio.csvIoUsesFiles
                  ? 'Export applications.csv'
                  : 'Copy applications CSV')),
          PopupMenuItem(
              value: 'xe',
              child: Text(csvio.csvIoUsesFiles ? 'Export events.csv' : 'Copy events CSV')),
          PopupMenuItem(
              value: 'imp',
              child: Text(csvio.csvIoUsesFiles ? 'Import CSV…' : 'Import CSV from clipboard')),
          const PopupMenuItem(value: 'undoimp', child: Text('Undo an import…')),
          const PopupMenuItem(value: 'dup', child: Text('Remove duplicates…')),
        ],
      ),
    ]);
    final title = Row(mainAxisSize: MainAxisSize.min, children: [
      Text('求職', style: serifHk(size: 19, color: C.red)),
      const SizedBox(width: 7),
      Text('CAREER', style: disp(size: 18, w: FontWeight.w700, color: C.ink)),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 640) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [title, const Spacer(), actions]),
            const SizedBox(height: 8),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
          ]);
        }
        return Row(children: [
          title,
          const SizedBox(width: 18),
          tabs,
          const Spacer(),
          actions,
        ]);
      }),
    );
  }
}

// ---------------- shared bits ----------------

Widget _sectionTitle(String text, {Color color = C.ink3, String? count}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 7),
      child: Row(children: [
        Text(text, style: mono(size: 10, color: color, w: FontWeight.w700).copyWith(letterSpacing: 1)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(count, style: mono(size: 10, color: C.ink3)),
        ],
      ]),
    );

Widget _none(String text) => Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(text, style: const TextStyle(fontSize: 12.5, color: C.ink3)),
    );

Widget _card({required Widget child, VoidCallback? onTap, Color? edge}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: C.paper,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: C.line),
            ),
            foregroundDecoration: edge == null
                ? null
                : BoxDecoration(
                    border: Border(left: BorderSide(color: edge, width: 4)),
                    borderRadius: BorderRadius.circular(9),
                  ),
            child: child,
          ),
        ),
      ),
    );

Widget _pill(String text, Color color, {bool filled = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : null,
        border: Border.all(color: color, width: 1.3),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text,
          style: mono(size: 9.5, color: filled ? C.creamTxt : color, w: FontWeight.w700)),
    );

Widget _sponsorPill(String s) => switch (s) {
      'no-sponsorship' => Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: C.red),
          const SizedBox(width: 3),
          _pill('NO SPONSORSHIP', C.red, filled: true),
        ]),
      'cpt-ok' => _pill('CPT OK', C.green),
      _ => _pill('SPONSOR ?', C.ink3),
    };

bool _isRealTime(DateTime d) =>
    !(d.hour == 0 && d.minute == 0) && !(d.hour == 23 && d.minute == 59);

void _open(BuildContext context, AgendaItem i) {
  if (i.app != null) showApplicationForm(context, existing: i.app);
  if (i.event != null) showEventForm(context, existing: i.event);
}

Widget _agendaRow(BuildContext context, AgendaItem i,
    {Color accent = C.ink3, String origin = 'you'}) {
  // Midnight / 23:59 are how date-only entries are stored, not real times,
  // so those show as just the day.
  final when = Text(
      _isRealTime(i.when)
          ? '${_fmtDay(i.when)} · ${isoDateTime(i.when).substring(11)}'
          : _fmtDay(i.when),
      style: mono(size: 11, color: C.ink2, w: FontWeight.w700));
  final title = Text(i.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: C.ink));
  final marks = <Widget>[
    if (i.event?.status == 'signed-up') ...[
      const SizedBox(width: 6),
      const Tooltip(message: 'Signed up', child: Icon(Icons.check_circle, size: 15, color: C.green)),
    ],
    const SizedBox(width: 6),
    originMark(origin),
    const SizedBox(width: 6),
    _pill(i.detail.toUpperCase(), accent),
  ];
  return _card(
    onTap: () => _open(context, i),
    edge: accent,
    child: LayoutBuilder(
      builder: (_, c) => c.maxWidth < 420
          // Phone: date and tags on one line, the title full width below it.
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: when), ...marks]),
              const SizedBox(height: 5),
              title,
            ])
          : Row(children: [
              SizedBox(width: 136, child: when),
              Expanded(child: title),
              ...marks,
            ]),
    ),
  );
}

// ---------------- Overview: schedule | goals ----------------

/// Accent for a schedule line, by what kind of thing it is.
Color _kindColor(AgendaItem i) => switch (i.detail) {
      'sign-up opens' || 'sign-up closes' => C.red,
      'deadline' || 'application closes' => C.mustard,
      'hackathon' || 'game-jam' => C.plum,
      'career-fair' || 'company-event' || 'info-session' => C.navy,
      _ => i.app != null ? C.greenD : C.teal,
    };

/// Where an item came from, as a small mark. Your own items carry none, so
/// anything marked stands out as not typed in by you.
Widget originMark(String from) {
  final (IconData icon, String label, Color color) = switch (from) {
    'cadence' => (Icons.auto_awesome, 'SUGGESTED', C.plum),
    'import' => (Icons.file_download_outlined, 'IMPORTED', C.ink3),
    'email' => (Icons.mail_outline, 'EMAIL', C.teal),
    _ => (Icons.person_outline, '', C.ink3),
  };
  if (label.isEmpty) return const SizedBox.shrink();
  return Tooltip(
    message: originLabel[from] ?? from,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: mono(size: 8.5, color: color, w: FontWeight.w700)),
      ]),
    ),
  );
}

String _from(AgendaItem i) => i.event?.from ?? i.app?.from ?? 'you';

/// Which heading a schedule item sits under: the next two days, this week,
/// next week, then by month.
String _bucket(DateTime when, DateTime now) {
  if (when.isBefore(now.add(const Duration(hours: 48)))) return 'NEXT 48 HOURS';
  final nextWeek = weekStart(now).add(const Duration(days: 7));
  if (when.isBefore(nextWeek)) return 'THIS WEEK';
  if (when.isBefore(nextWeek.add(const Duration(days: 7)))) return 'NEXT WEEK';
  const months = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY',
    'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
  return '${months[when.month - 1]} ${when.year}';
}

Widget _stat(String label, String value, String? sub) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono(size: 9, color: C.ink3, w: FontWeight.w700)),
        Text(value, style: disp(size: 20, w: FontWeight.w700, color: C.ink)),
        if (sub != null) Text(sub, style: const TextStyle(fontSize: 10.5, color: C.ink3)),
      ],
    );

class _OverviewTab extends StatelessWidget {
  final _CareerPageState page;
  const _OverviewTab(this.page);

  @override
  Widget build(BuildContext context) {
    if (store.applications.isEmpty && store.trackEvents.isEmpty && store.goals.isEmpty) {
      return _empty(context);
    }
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 760) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 3, child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
              children: _schedule(context))),
          Expanded(flex: 2, child: _goalsBoard(context)),
        ]);
      }
      // Narrow: one pane at a time, switched by two tabs.
      Widget seg(String id, String label) {
        final on = page._narrowPane == id;
        return Expanded(
          child: InkWell(
            onTap: () => page._update(() => page._narrowPane = id),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: on ? C.green : C.line, width: on ? 2.5 : 1)),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? C.greenD : C.ink3)),
            ),
          ),
        );
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [seg('schedule', 'Schedule'), seg('goals', 'Goals & metrics')]),
        Expanded(
          child: page._narrowPane == 'goals'
              ? _goalsBoard(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                  children: _schedule(context),
                ),
        ),
      ]);
    });
  }

  // ---- left: everything coming up, however far out ----
  List<Widget> _schedule(BuildContext context) {
    final now = DateTime.now();
    final a = CareerAgenda.build(store.applications, store.trackEvents);
    final s = CareerSchedule.build(store.applications, store.trackEvents);
    final groups = <String, List<AgendaItem>>{};
    for (final i in s.upcoming) {
      (groups[_bucket(i.when, now)] ??= []).add(i);
    }
    return [
      if (a.followUps.isNotEmpty) ...[
        _sectionTitle('FOLLOW-UPS DUE', color: C.mustard, count: '${a.followUps.length}'),
        for (final app in a.followUps)
        _card(
          onTap: () => showApplicationForm(context, existing: app),
          edge: C.mustard,
          child: Row(children: [
            SizedBox(
                width: 118,
                child: Text(fmtWhen(app.nextActionDate),
                    style: mono(size: 11, color: C.ink2, w: FontWeight.w700))),
            Expanded(
              child: Text('${app.nextAction ?? 'Next step'} — ${app.company}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: C.ink)),
            ),
          ]),
        ),
      ],

      if (a.ghostCandidates.isNotEmpty) ...[
        _sectionTitle('NO REPLY IN 6 WEEKS'),
        for (final app in a.ghostCandidates)
          _card(
            child: Row(children: [
              Expanded(
                child: Text('${app.company} — applied ${fmtWhen(app.dateApplied)}',
                    style: const TextStyle(fontSize: 13, color: C.ink2)),
              ),
              TextButton(
                onPressed: () => store.setAppStatus(app, 'ghosted'),
                child: const Text('Mark ghosted'),
              ),
            ]),
          ),
      ],

      if (s.running.isNotEmpty) ...[
        _sectionTitle('HAPPENING NOW', color: C.green, count: '${s.running.length}'),
        for (final i in s.running) _agendaRow(context, i, accent: C.green, origin: _from(i)),
      ],

      if (s.upcoming.isEmpty && s.running.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _none('Nothing on the calendar yet — add an event or an application deadline.'),
        ),
      for (final g in groups.entries) ...[
        _sectionTitle(g.key,
            color: g.key == 'NEXT 48 HOURS' ? C.red : C.navy, count: '${g.value.length}'),
        for (final i in g.value) _agendaRow(context, i, accent: _kindColor(i), origin: _from(i)),
      ],

      if (s.tbd.isNotEmpty) ...[
        _sectionTitle('DATE TBD', count: '${s.tbd.length}'),
        for (final e in s.tbd)
          _card(
            onTap: () => showEventForm(context, existing: e),
            child: Row(children: [
              Expanded(
                child: Text(e.name,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: C.ink2)),
              ),
              originMark(e.from),
              const SizedBox(width: 6),
              _pill(e.type.toUpperCase(), C.ink3),
            ]),
          ),
      ],
    ];
  }

  // ---- right: the goals board — the mahjong table's felt, with the meters
  // and goals laid on it as ivory tiles ----
  Widget _goalsBoard(BuildContext context) => FeltTable(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          children: _goals(context),
        ),
      );

  /// A cream label on the felt.
  Widget _feltTitle(String text, {String? count}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
        child: Row(children: [
          Text(text,
              style: mono(size: 10, color: C.creamTxt.withValues(alpha: .8), w: FontWeight.w700)
                  .copyWith(letterSpacing: 1.2)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(count, style: mono(size: 10, color: C.mustard, w: FontWeight.w700)),
          ],
        ]),
      );

  List<Widget> _goals(BuildContext context) {
    final a = CareerAgenda.build(store.applications, store.trackEvents);
    final stats = AppStats.of(store.applications);
    final applied = a.appliedThisWeek;
    final now = DateTime.now();
    final evs = store.trackEvents;
    final signedUp = evs.where((e) =>
        e.status == 'signed-up' && !(e.endAt?.isBefore(now) ?? false)).length;
    final attended = evs.where((e) => e.status == 'attended').length;
    final jams = evs.where((e) =>
        e.status == 'attended' && (e.type == 'hackathon' || e.type == 'game-jam')).length;

    final onTarget = applied >= weeklyTargetMin;
    return [
      // Header, like the mahjong wall's 麻雀.
      Row(children: [
        Text('目標',
            style: serifHk(size: 26, color: C.creamTxt).copyWith(shadows: const [
              Shadow(color: Color(0x66000000), offset: Offset(1, 2), blurRadius: 4),
            ])),
        const SizedBox(width: 9),
        Text('GOALS', style: disp(size: 15, w: FontWeight.w600, color: C.mustard)),
        const Spacer(),
        TextButton.icon(
          onPressed: () => showGoalForm(context),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Goal'),
          style: TextButton.styleFrom(
            backgroundColor: C.mustard,
            foregroundColor: C.ink,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ]),

      _feltTitle('APPLIED THIS WEEK'),
      IvoryTile(
        lip: onTarget ? tileGreen : C.mustard,
        child: Row(children: [
          Text('$applied', style: disp(size: 34, w: FontWeight.w700, color: C.ink)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(onTarget ? 'on target this week' : 'target $weeklyTargetMin–$weeklyTargetMax a week',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.ink2)),
              const SizedBox(height: 7),
              _meter(applied / weeklyTargetMax, onTarget ? C.green : C.mustard),
            ]),
          ),
        ]),
      ),

      _feltTitle('PIPELINE'),
      IvoryTile(
        child: _statRow([
          ('Sent', '${stats.sent}', null),
          ('Response', stats.responseRate == null ? '—' : '${(stats.responseRate! * 100).round()}%', null),
          ('Interviews',
              '${(stats.byStatus['interview'] ?? 0) + (stats.byStatus['final-round'] ?? 0)}', null),
          ('Offers', '${stats.byStatus['offer'] ?? 0}', null),
        ]),
      ),

      _feltTitle('EVENTS'),
      IvoryTile(
        lip: C.plum,
        child: _statRow([
          ('Signed up', '$signedUp', 'upcoming'),
          ('Attended', '$attended', null),
          ('Hacks & jams', '$jams', 'attended'),
        ]),
      ),

      _feltTitle('MY GOALS', count: '${store.goals.length}'),
      if (store.goals.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Text('Set a target — e.g. apply to 40 by 1 Dec, or 3 hackathons this semester.',
              style: TextStyle(fontSize: 12.5, color: C.creamTxt.withValues(alpha: .75), height: 1.4)),
        ),
      for (final g in store.goals) _goalCard(context, g, now),
    ];
  }

  /// Stats spread evenly across a tile, each a small label over a big number.
  Widget _statRow(List<(String, String, String?)> stats) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (label, value, sub) in stats)
          Expanded(child: _stat(label, value, sub)),
      ]);

  Widget _meter(double value, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1).toDouble(),
          minHeight: 8,
          backgroundColor: const Color(0xFFD9CFB4),
          color: color,
        ),
      );

  Widget _goalCard(BuildContext context, Goal g, DateTime now) {
    final have = g.progress(store.applications, store.trackEvents);
    final done = have >= g.target;
    // On pace = at least the share of the target that the elapsed share of the
    // window calls for. Only meaningful with both a start and an end date.
    final from = parseWhen(g.since), by = parseWhen(g.due, endOfDay: true);
    String? pace;
    var behind = false;
    if (!done && by != null) {
      final left = DateTime(by.year, by.month, by.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      pace = left < 0 ? 'past due' : left == 0 ? 'due today' : '$left days left';
      behind = left < 0;
      if (from != null && by.isAfter(from) && left > 0) {
        final elapsed = now.difference(from).inMinutes / by.difference(from).inMinutes;
        behind = have < g.target * elapsed.clamp(0, 1);
        pace = '$pace · ${behind ? 'behind pace' : 'on pace'}';
      }
    }
    final color = done ? C.green : behind ? C.red : C.mustard;
    return IvoryTile(
      onTap: () => showGoalForm(context, existing: g),
      lip: done ? tileGreen : color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(g.title,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink)),
          ),
          Text('$have / ${g.target}', style: mono(size: 12, color: C.ink, w: FontWeight.w700)),
          if (g.metric == 'manual') ...[
            const SizedBox(width: 4),
            _bump(Icons.remove, () => store.bumpGoal(g, -1)),
            _bump(Icons.add, () => store.bumpGoal(g, 1)),
          ],
        ]),
        const SizedBox(height: 6),
        _meter(have / g.target, color),
        const SizedBox(height: 5),
        Text(
          [
            goalMetricLabel[g.metric] ?? g.metric,
            if (g.since != null) 'since ${fmtWhen(g.since)}',
            if (g.due != null) 'by ${fmtWhen(g.due)}',
            if (done) 'done ✓' else if (pace != null) pace,
          ].join(' · '),
          style: TextStyle(fontSize: 11.5, color: behind ? C.red : C.ink3),
        ),
      ]),
    );
  }

  Widget _bump(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: C.greenD),
        ),
      );

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.work_outline, size: 40, color: C.ink3),
            const SizedBox(height: 10),
            const Text('Track internship applications and career events here.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: C.ink2)),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              // A starting list lives in your own CSVs (kept out of this
              // public repo), so importing is the way in.
              FilledButton.icon(
                onPressed: page._import,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import CSV'),
                style: FilledButton.styleFrom(backgroundColor: C.green),
              ),
              OutlinedButton.icon(
                onPressed: page._add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add your first item'),
              ),
            ]),
          ]),
        ),
      );
}

// ---------------- Applications ----------------

class _AppsTab extends StatelessWidget {
  final _CareerPageState page;
  const _AppsTab(this.page);

  List<Application> get _filtered => store.applications.where((a) =>
      (page._fTrack == null || a.track == page._fTrack) &&
      (page._fStatus == null || a.status == page._fStatus) &&
      (page._fSponsor == null || a.sponsorship == page._fSponsor)).toList();

  @override
  Widget build(BuildContext context) {
    final stats = AppStats.of(store.applications);
    final applied = CareerAgenda.build(store.applications, const []).appliedThisWeek;
    final due = store.applications.where((a) => dueWithin(a, 7)).toList()
      ..sort((x, y) => (x.deadline ?? x.nextActionDate ?? '')
          .compareTo(y.deadline ?? y.nextActionDate ?? ''));
    final apps = _filtered;
    final statuses = page._fStatus == null ? appStatuses : [page._fStatus!];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Wrap(spacing: 18, runSpacing: 6, children: [
          _stat('This week', '$applied', 'target $weeklyTargetMin–$weeklyTargetMax'),
          _stat('Sent', '${stats.sent}', null),
          _stat('Response rate',
              stats.responseRate == null ? '—' : '${(stats.responseRate! * 100).round()}%', null),
          _stat('Interviewing', '${(stats.byStatus['interview'] ?? 0) + (stats.byStatus['final-round'] ?? 0)}', null),
          _stat('Offers', '${stats.byStatus['offer'] ?? 0}', null),
        ]),
      ),
      if (due.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Wrap(spacing: 7, runSpacing: 6, children: [
            Text('DUE IN 7 DAYS', style: mono(size: 10, color: C.red, w: FontWeight.w700)),
            for (final a in due)
              ActionChip(
                onPressed: () => showApplicationForm(context, existing: a),
                visualDensity: VisualDensity.compact,
                label: Text(
                    '${a.company} · ${fmtWhen(a.deadline ?? a.nextActionDate)}',
                    style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _filter('Track', page._fTrack, appTracks, (v) => page._update(() => page._fTrack = v)),
          _filter('Status', page._fStatus, appStatuses, (v) => page._update(() => page._fStatus = v),
              labels: appStatusLabel),
          _filter('Sponsorship', page._fSponsor, sponsorships,
              (v) => page._update(() => page._fSponsor = v)),
        ]),
      ),
      Expanded(
        child: store.applications.isEmpty
            ? Center(child: _none('No applications yet — tap Add.'))
            : ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                children: [
                  for (final s in statuses)
                    _column(context, s, apps.where((a) => a.status == s).toList()),
                ],
              ),
      ),
    ]);
  }

  Widget _filter(String label, String? value, List<String> options, ValueChanged<String?> onPick,
          {Map<String, String>? labels}) =>
      PopupMenuButton<String>(
        tooltip: label,
        onSelected: (v) => onPick(v == '' ? null : v),
        itemBuilder: (_) => [
          PopupMenuItem(value: '', child: Text('All ${label.toLowerCase()}s')),
          for (final o in options) PopupMenuItem(value: o, child: Text(labels?[o] ?? o)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: value == null ? C.paper : C.green,
            border: Border.all(color: value == null ? C.line : C.green, width: 1.4),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(value == null ? label : '$label: ${labels?[value] ?? value}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: value == null ? C.ink2 : C.creamTxt)),
            Icon(Icons.arrow_drop_down, size: 18, color: value == null ? C.ink3 : C.creamTxt),
          ]),
        ),
      );

  Widget _column(BuildContext context, String status, List<Application> apps) => Container(
        width: 262,
        margin: const EdgeInsets.only(right: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: statusColor(status), borderRadius: BorderRadius.circular(7)),
            child: Row(children: [
              Text(appStatusLabel[status]!.toUpperCase(),
                  style: disp(size: 13, w: FontWeight.w700, color: C.creamTxt)),
              const Spacer(),
              Text('${apps.length}', style: mono(size: 11, color: C.creamTxt)),
            ]),
          ),
          Expanded(child: apps.isEmpty ? _none('—') : _grouped(context, status, apps)),
        ]),
      );

  /// One card per company: a company with several roles in this column is a
  /// single card that opens to list them, so a big imported list reads as
  /// "who" first. Built lazily, since a column can hold hundreds.
  Widget _grouped(BuildContext context, String status, List<Application> apps) {
    final byCompany = <String, List<Application>>{};
    for (final a in apps) {
      byCompany.putIfAbsent(a.company.trim().toLowerCase(), () => []).add(a);
    }
    final groups = byCompany.values.toList();
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, i) => groups[i].length == 1
          ? _appCard(context, groups[i].first)
          : _companyCard(context, status, groups[i]),
    );
  }

  Widget _tick(Application a, {double size = 20}) => a.status != 'to-apply'
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: 'Mark applied',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size + 10, height: size + 10),
          icon: Icon(Icons.check_circle_outline, size: size, color: C.green),
          onPressed: () => page._markApplied(a),
        );

  Widget _companyCard(BuildContext context, String status, List<Application> roles) {
    final key = '$status|${roles.first.company.trim().toLowerCase()}';
    final open = page._openCompanies.contains(key);
    void toggle() => page._update(() {
          if (!page._openCompanies.remove(key)) page._openCompanies.add(key);
        });
    return _card(
      onTap: toggle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(roles.first.company,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.ink)),
          ),
          _pill('${roles.length} ROLES', C.navy),
          Icon(open ? Icons.expand_less : Icons.expand_more, size: 20, color: C.ink3),
        ]),
        if (!open)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              roles.map((r) => r.role.isEmpty ? 'untitled role' : r.role).take(3).join(' · ') +
                  (roles.length > 3 ? ' …' : ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: C.ink2),
            ),
          )
        else ...[
          const SizedBox(height: 6),
          for (final r in roles)
            InkWell(
              onTap: () => showApplicationForm(context, existing: r),
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.role.isEmpty ? 'Untitled role' : r.role,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: C.ink)),
                      if (r.term != null || r.deadline != null || r.location != null)
                        Text(
                            [
                              if (r.term != null) r.term!,
                              if (r.location != null) r.location!,
                              if (r.deadline != null) 'closes ${fmtWhen(r.deadline)}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(size: 10, color: C.ink3)),
                    ]),
                  ),
                  _tick(r, size: 18),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _appCard(BuildContext context, Application a) => _card(
        onTap: () => showApplicationForm(context, existing: a),
        edge: a.sponsorship == 'no-sponsorship' ? C.red : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(a.company,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.ink)),
            ),
            _tick(a),
            PopupMenuButton<String>(
              tooltip: 'Move to…',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_horiz, size: 18, color: C.ink3),
              onSelected: (v) {
                if (v == '__link') {
                  csvio.openLink(a.link!);
                } else {
                  store.setAppStatus(a, v);
                }
              },
              itemBuilder: (_) => [
                if (a.link != null)
                  const PopupMenuItem(value: '__link', child: Text('Open posting')),
                for (final s in appStatuses)
                  if (s != a.status)
                    PopupMenuItem(value: s, child: Text('Move to ${appStatusLabel[s]}')),
              ],
            ),
          ]),
          if (a.role.isNotEmpty)
            Text(a.role,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: C.ink2)),
          const SizedBox(height: 7),
          Wrap(spacing: 5, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _pill(a.track.toUpperCase(), C.navy),
            _sponsorPill(a.sponsorship),
            if (a.cvVersion == 'gaming') _pill('GAMING CV', C.mustard),
            originMark(a.from),
          ]),
          if (a.dateApplied != null || a.deadline != null) ...[
            const SizedBox(height: 6),
            Text(
                [
                  if (a.dateApplied != null) 'applied ${fmtWhen(a.dateApplied)}',
                  if (a.deadline != null) 'closes ${fmtWhen(a.deadline)}',
                ].join(' · '),
                style: mono(size: 10, color: C.ink3)),
          ],
          if (a.nextAction != null) ...[
            const SizedBox(height: 4),
            Text('→ ${a.nextAction}${a.nextActionDate == null ? '' : ' (${fmtWhen(a.nextActionDate)})'}',
                style: const TextStyle(fontSize: 12, color: C.greenD, fontWeight: FontWeight.w600)),
          ],
        ]),
      );
}

// ---------------- Events ----------------

class _EventsTab extends StatelessWidget {
  final _CareerPageState page;
  const _EventsTab(this.page);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextWeek = weekStart(now).add(const Duration(days: 7));
    final weekAfter = nextWeek.add(const Duration(days: 7));
    final alerts = CareerAgenda.build(const [], store.trackEvents)
        .urgent
        .where((u) => u.detail.startsWith('sign-up'))
        .toList();

    final thisWeek = <TrackEvent>[], next = <TrackEvent>[], later = <TrackEvent>[],
        tbd = <TrackEvent>[], past = <TrackEvent>[];
    for (final e in store.trackEvents) {
      final s = e.startAt;
      final end = e.endAt;
      if (s == null) {
        tbd.add(e);
      } else if (end != null && end.isBefore(today)) {
        past.add(e);
      } else if (s.isBefore(nextWeek)) {
        thisWeek.add(e);
      } else if (s.isBefore(weekAfter)) {
        next.add(e);
      } else {
        later.add(e);
      }
    }
    int byStart(TrackEvent x, TrackEvent y) => x.startAt!.compareTo(y.startAt!);
    thisWeek.sort(byStart);
    next.sort(byStart);
    later.sort(byStart);
    past.sort((x, y) => byStart(y, x));

    if (store.trackEvents.isEmpty) return Center(child: _none('No events yet — tap Add.'));
    return ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 20), children: [
      if (alerts.isNotEmpty) ...[
        _sectionTitle('SIGN-UP ALERTS · NEXT 48 HOURS', color: C.red),
        for (final i in alerts) _agendaRow(context, i, accent: C.red, origin: _from(i)),
      ],
      _group(context, 'THIS WEEK', thisWeek),
      _group(context, 'NEXT WEEK', next),
      _group(context, 'LATER', later),
      _group(context, 'DATE TBD', tbd),
      _group(context, 'PAST', past),
    ]);
  }

  Widget _group(BuildContext context, String title, List<TrackEvent> events) {
    if (events.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle(title, count: '${events.length}'),
      for (final e in events) _eventCard(context, e),
    ]);
  }

  Widget _eventCard(BuildContext context, TrackEvent e) {
    final faded = e.status == 'skipped' || e.status == 'missed';
    return Opacity(
      opacity: faded ? .55 : 1,
      child: _card(
        onTap: () => showEventForm(context, existing: e),
        edge: e.status == 'signed-up' ? C.green : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(e.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.ink)),
            ),
            PopupMenuButton<String>(
              tooltip: 'Status',
              onSelected: (v) {
                if (v == '__link') {
                  csvio.openLink(e.link!);
                } else {
                  store.setEventStatus(e, v);
                }
              },
              itemBuilder: (_) => [
                if (e.link != null) const PopupMenuItem(value: '__link', child: Text('Open link')),
                for (final s in eventStatuses)
                  if (s != e.status) PopupMenuItem(value: s, child: Text('Mark $s')),
              ],
              child: _pill(e.status.toUpperCase(), e.status == 'signed-up' ? C.green : C.ink3,
                  filled: e.status == 'signed-up'),
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_fmtRange(e), style: mono(size: 10.5, color: C.ink2, w: FontWeight.w700)),
            _pill(e.type.toUpperCase(), C.navy),
            originMark(e.from),
            if (e.location != null) Text(e.location!, style: const TextStyle(fontSize: 12, color: C.ink3)),
          ]),
          if (e.signupOpens != null || e.signupCloses != null) ...[
            const SizedBox(height: 4),
            Text(
                'sign-up ${e.signupOpens == null ? '' : 'opens ${fmtWhen(e.signupOpens)}'}'
                '${e.signupOpens != null && e.signupCloses != null ? ' · ' : ''}'
                '${e.signupCloses == null ? '' : 'closes ${fmtWhen(e.signupCloses)}'}',
                style: const TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w600)),
          ],
          if (e.prep != null) ...[
            const SizedBox(height: 5),
            Text(e.prep!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: C.ink2)),
          ],
        ]),
      ),
    );
  }
}
