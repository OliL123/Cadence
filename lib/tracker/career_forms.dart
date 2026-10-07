// Add/edit forms for applications and events.
import 'package:flutter/material.dart';

import '../palette.dart';
import '../store.dart';
import '../widgets/type.dart';
import 'tracker_models.dart';

/// Near-white fields on the cream dialog, so each one reads as a field, with
/// the label always sitting on the border — an empty field shows its label up
/// there and a pale hint inside, never a label that looks like filled-in text.
const _fieldFill = Color(0xFFFFFCF4);

InputDecoration _dec(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint ?? '—',
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: const TextStyle(fontSize: 13, color: C.ink2, fontWeight: FontWeight.w600),
      floatingLabelStyle:
          const TextStyle(fontSize: 13, color: C.ink2, fontWeight: FontWeight.w700),
      hintStyle: TextStyle(fontSize: 14, color: C.ink3.withValues(alpha: .7)),
      isDense: true,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFC9B98F), width: 1.2)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: C.green, width: 1.8)),
    );

/// A small heading that splits a form into sections.
Widget _heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(children: [
        Text(text,
            style: mono(size: 10, color: C.greenD, w: FontWeight.w700).copyWith(letterSpacing: 1.3)),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1, thickness: 1, color: C.line)),
      ]),
    );

Widget _text(TextEditingController c, String label,
        {String? hint, int maxLines = 1, TextInputType? kb}) =>
    TextField(
      controller: c,
      maxLines: maxLines,
      minLines: 1,
      keyboardType: kb,
      style: const TextStyle(fontSize: 14, color: C.ink),
      decoration: _dec(label, hint: hint),
    );

Widget _drop(String label, String value, List<String> options,
        ValueChanged<String> onChanged, {Map<String, String>? labels}) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: _dec(label),
      style: const TextStyle(fontSize: 14, color: C.ink),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(labels?[o] ?? o, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );

/// Two fields side by side on wide forms, stacked on narrow ones.
Widget _pair(Widget a, Widget b) => LayoutBuilder(
      builder: (_, c) => c.maxWidth < 420
          ? Column(children: [a, const SizedBox(height: 10), b])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: a),
              const SizedBox(width: 10),
              Expanded(child: b),
            ]),
    );

/// A date (and optionally a time) as "yyyy-mm-dd" / "yyyy-mm-dd HH:mm".
class WhenField extends StatefulWidget {
  final String label;
  final String? initial;
  final bool withTime;
  final ValueChanged<String?> onChanged;
  const WhenField(
      {super.key,
      required this.label,
      required this.initial,
      required this.onChanged,
      this.withTime = false});
  @override
  State<WhenField> createState() => _WhenFieldState();
}

class _WhenFieldState extends State<WhenField> {
  DateTime? _date;
  final _time = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = parseWhen(widget.initial);
    if (d != null) {
      _date = DateTime(d.year, d.month, d.day);
      if (hasTime(widget.initial)) _time.text = isoDateTime(d).substring(11);
    }
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  void _emit() {
    if (_date == null) return widget.onChanged(null);
    final t = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    if (widget.withTime && t != null) {
      final h = int.parse(t[1]!), m = int.parse(t[2]!);
      if (h < 24 && m < 60) {
        return widget.onChanged(
            isoDateTime(DateTime(_date!.year, _date!.month, _date!.day, h, m)));
      }
    }
    widget.onChanged(isoDate(_date!));
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return;
    setState(() => _date = d);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: _dec(widget.label).copyWith(
          contentPadding: const EdgeInsets.fromLTRB(11, 6, 4, 6)),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: _pick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.event, size: 16, color: C.ink3),
                const SizedBox(width: 6),
                Text(_date == null ? 'Set date' : isoDate(_date!),
                    style: TextStyle(
                        fontSize: 14, color: _date == null ? C.ink3 : C.ink)),
              ]),
            ),
          ),
        ),
        if (widget.withTime && _date != null)
          SizedBox(
            width: 70,
            child: TextField(
              controller: _time,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.datetime,
              style: const TextStyle(fontSize: 14, color: C.ink),
              decoration: const InputDecoration(
                  isDense: true, border: InputBorder.none, hintText: 'HH:mm'),
              onChanged: (_) => _emit(),
            ),
          ),
        if (_date != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Clear',
            icon: const Icon(Icons.close, size: 16, color: C.ink3),
            onPressed: () {
              setState(() {
                _date = null;
                _time.clear();
              });
              _emit();
            },
          ),
      ]),
    );
  }
}

Widget _formShell(BuildContext context,
    {required String title,
    required List<Widget> fields,
    required VoidCallback onSave,
    VoidCallback? onDelete}) {
  // On a phone the form takes the whole screen: more room to read and type,
  // and the keyboard doesn't squeeze it into a sliver.
  final phone = MediaQuery.sizeOf(context).width < 560;
  final body = Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.line)),
          ),
          child: Row(children: [
            Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: disp(size: 19, w: FontWeight.w700, color: C.ink))),
            IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: C.ink3),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Flexible(
          fit: phone ? FlexFit.tight : FlexFit.loose,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: Column(children: [
              for (final f in fields) ...[f, const SizedBox(height: 12)],
            ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 20, 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: C.line)),
          ),
          child: Row(children: [
            if (onDelete != null)
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: C.red),
              ),
            const Spacer(),
            TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: C.ink3),
                child: const Text('Cancel')),
            const SizedBox(width: 6),
            FilledButton(
                onPressed: onSave,
                style: FilledButton.styleFrom(backgroundColor: C.green),
                child: const Text('Save')),
          ]),
        ),
      ]);
  if (phone) {
    return Dialog.fullscreen(
      backgroundColor: C.paper2,
      child: SafeArea(child: body),
    );
  }
  return Dialog(
    backgroundColor: C.paper2,
    insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: body),
  );
}

Future<bool> _confirmDelete(BuildContext context, String what) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.paper2,
        title: Text('Delete $what?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: C.red),
              child: const Text('Delete')),
        ],
      ),
    ) ??
    false;

// ---------------- application ----------------

Future<void> showApplicationForm(BuildContext context, {Application? existing}) =>
    showDialog(context: context, builder: (_) => _AppForm(existing: existing));

class _AppForm extends StatefulWidget {
  final Application? existing;
  const _AppForm({this.existing});
  @override
  State<_AppForm> createState() => _AppFormState();
}

class _AppFormState extends State<_AppForm> {
  late final Application d; // a draft; copied into the real one on save
  late final _company = TextEditingController(text: d.company);
  late final _role = TextEditingController(text: d.role);
  late final _term = TextEditingController(text: d.term ?? 'Summer 2027');
  late final _location = TextEditingController(text: d.location);
  late final _link = TextEditingController(text: d.link);
  late final _grad = TextEditingController(text: d.gradReq);
  late final _contact = TextEditingController(text: d.contact);
  late final _next = TextEditingController(text: d.nextAction);
  late final _notes = TextEditingController(text: d.notes);
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    d = e == null ? Application(id: 0, company: '') : Application.fromJson(e.toJson());
  }

  @override
  void dispose() {
    for (final c in [_company, _role, _term, _location, _link, _grad, _contact, _next, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (_company.text.trim().isEmpty) {
      setState(() => _error = 'Company is required');
      return;
    }
    final t = widget.existing ?? Application(id: 0, company: '');
    t
      ..company = _company.text.trim()
      ..role = _role.text.trim()
      ..track = d.track
      ..term = _v(_term)
      ..location = _v(_location)
      ..link = _v(_link)
      ..source = d.source
      ..sponsorship = d.sponsorship
      ..gradReq = _v(_grad)
      ..cvVersion = d.cvVersion
      ..status = d.status
      ..dateApplied = d.dateApplied
      ..deadline = d.deadline
      ..contact = _v(_contact)
      ..nextAction = _v(_next)
      ..nextActionDate = d.nextActionDate
      ..notes = _v(_notes)
      ..origin = d.origin;
    // Marking it applied without a date: assume today.
    if (t.status != 'to-apply' && t.dateApplied == null) {
      t.dateApplied = isoDate(DateTime.now());
    }
    store.saveApplication(t);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return _formShell(
      context,
      title: e == null ? 'New application' : '${e.company} — ${e.role}',
      onSave: _save,
      onDelete: e == null
          ? null
          : () async {
              if (await _confirmDelete(context, 'this application')) {
                store.deleteApplication(e);
                if (context.mounted) Navigator.pop(context);
              }
            },
      fields: [
        if (_error != null)
          Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13))),
        _heading('THE ROLE'),
        _pair(_text(_company, 'Company *'), _text(_role, 'Role', hint: 'Software Engineering Intern')),
        _pair(
          _drop('Status', d.status, appStatuses, (v) => setState(() => d.status = v),
              labels: appStatusLabel),
          _drop('Track', d.track, appTracks, (v) => d.track = v),
        ),
        _heading('ELIGIBILITY'),
        _pair(
          _drop('Sponsorship (F-1 / CPT)', d.sponsorship, sponsorships, (v) => setState(() => d.sponsorship = v),
              labels: const {'cpt-ok': 'CPT OK', 'no-sponsorship': 'No sponsorship', 'unclear': 'Unclear'}),
          _text(_grad, 'Grad year requirement', hint: '2028 grads'),
        ),
        if (d.sponsorship == 'no-sponsorship')
          const _Warn('This posting says no sponsorship — check before spending time on it.'),
        _heading('POSTING'),
        _pair(_text(_term, 'Term'), _text(_location, 'Location', hint: 'City or Remote')),
        _pair(
          _drop('Found on', d.source, appSources, (v) => d.source = v),
          _drop('CV version', d.cvVersion, cvVersions, (v) => d.cvVersion = v),
        ),
        _text(_link, 'Posting link', hint: 'https://…', kb: TextInputType.url),
        _heading('DATES'),
        _pair(
          WhenField(label: 'Date applied', initial: d.dateApplied, onChanged: (v) => d.dateApplied = v),
          WhenField(label: 'Application deadline', initial: d.deadline, onChanged: (v) => d.deadline = v),
        ),
        _heading('NEXT STEP'),
        _pair(
          _text(_next, 'Next action', hint: 'follow up, OA due, prep interview'),
          WhenField(label: 'Next action date', initial: d.nextActionDate,
              onChanged: (v) => d.nextActionDate = v),
        ),
        _text(_contact, 'Contact', hint: 'Recruiter / referral name + email'),
        _heading('NOTES'),
        _text(_notes, 'Notes', hint: 'Anything worth remembering', maxLines: 5),
        _originDrop(d.from, (v) => d.origin = v),
      ],
    );
  }
}

class _Warn extends StatelessWidget {
  final String text;
  const _Warn(this.text);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: C.red.withValues(alpha: .07),
          border: Border.all(color: C.red.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: C.red),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: C.red))),
        ]),
      );
}

// ---------------- event ----------------

Future<void> showEventForm(BuildContext context, {TrackEvent? existing}) =>
    showDialog(context: context, builder: (_) => _EventForm(existing: existing));

class _EventForm extends StatefulWidget {
  final TrackEvent? existing;
  const _EventForm({this.existing});
  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  late final TrackEvent d;
  late final _name = TextEditingController(text: d.name);
  late final _location = TextEditingController(text: d.location);
  late final _link = TextEditingController(text: d.link);
  late final _prep = TextEditingController(text: d.prep);
  late final _outcome = TextEditingController(text: d.outcome);
  late final _company = TextEditingController(text: d.relatedCompany);
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    d = e == null ? TrackEvent(id: 0, name: '') : TrackEvent.fromJson(e.toJson());
  }

  @override
  void dispose() {
    for (final c in [_name, _location, _link, _prep, _outcome, _company]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final t = widget.existing ?? TrackEvent(id: 0, name: '');
    t
      ..name = _name.text.trim()
      ..type = d.type
      ..start = d.start
      ..end = d.end
      ..location = _v(_location)
      ..link = _v(_link)
      ..signupOpens = d.signupOpens
      ..signupCloses = d.signupCloses
      ..status = d.status
      ..prep = _v(_prep)
      ..outcome = _v(_outcome)
      ..relatedCompany = _v(_company)
      ..origin = d.origin;
    store.saveEvent(t);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return _formShell(
      context,
      title: e == null ? 'New event' : e.name,
      onSave: _save,
      onDelete: e == null
          ? null
          : () async {
              if (await _confirmDelete(context, 'this event')) {
                store.deleteEvent(e);
                if (context.mounted) Navigator.pop(context);
              }
            },
      fields: [
        if (_error != null)
          Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13))),
        _heading('THE EVENT'),
        _text(_name, 'Name *'),
        _pair(
          _drop('Type', d.type, eventTypes, (v) => d.type = v),
          _drop('Status', d.status, eventStatuses, (v) => d.status = v),
        ),
        _heading('WHEN'),
        _pair(
          WhenField(label: 'Starts (blank = TBD)', initial: d.start, withTime: true,
              onChanged: (v) => d.start = v),
          WhenField(label: 'Ends', initial: d.end, withTime: true, onChanged: (v) => d.end = v),
        ),
        _heading('SIGN-UP WINDOW'),
        _pair(
          WhenField(label: 'Sign-up opens', initial: d.signupOpens, withTime: true,
              onChanged: (v) => d.signupOpens = v),
          WhenField(label: 'Sign-up closes', initial: d.signupCloses, withTime: true,
              onChanged: (v) => d.signupCloses = v),
        ),
        _heading('WHERE'),
        _pair(_text(_location, 'Location', hint: 'Room, city, or Online'),
            _text(_company, 'Related company', hint: 'Company running it, if any')),
        _text(_link, 'Link', hint: 'https://…', kb: TextInputType.url),
        _heading('NOTES'),
        _text(_prep, 'Prep — what to do beforehand', hint: 'What to research or bring', maxLines: 4),
        _text(_outcome, 'Outcome — who you met, what came of it',
            hint: 'Fill in afterwards', maxLines: 4),
        _originDrop(d.from, (v) => d.origin = v),
      ],
    );
  }
}

/// Where an item came from (you, a Cadence suggestion, an import, email).
/// "You" is stored as no origin, like every item made before this existed.
Widget _originDrop(String value, ValueChanged<String?> onChanged) => _drop(
    'Added via', value, origins, (v) => onChanged(v == 'you' ? null : v),
    labels: originLabel);

// ---------------- goal ----------------

Future<void> showGoalForm(BuildContext context, {Goal? existing}) =>
    showDialog(context: context, builder: (_) => _GoalForm(existing: existing));

class _GoalForm extends StatefulWidget {
  final Goal? existing;
  const _GoalForm({this.existing});
  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final Goal d;
  late final _title = TextEditingController(text: d.title);
  late final _target = TextEditingController(text: '${d.target}');
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    d = e == null
        ? Goal(id: 0, title: '', target: 10, metric: 'applied', since: isoDate(DateTime.now()))
        : Goal.fromJson(e.toJson());
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  void _save() {
    final target = int.tryParse(_target.text.trim());
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the goal a name');
      return;
    }
    if (target == null || target < 1) {
      setState(() => _error = 'Target must be a whole number, 1 or more');
      return;
    }
    final t = widget.existing ?? Goal(id: 0, title: '');
    t
      ..title = _title.text.trim()
      ..target = target
      ..metric = d.metric
      ..since = d.since
      ..due = d.due;
    store.saveGoal(t);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return _formShell(
      context,
      title: e == null ? 'New goal' : e.title,
      onSave: _save,
      onDelete: e == null
          ? null
          : () async {
              if (await _confirmDelete(context, 'this goal')) {
                store.deleteGoal(e);
                if (context.mounted) Navigator.pop(context);
              }
            },
      fields: [
        if (_error != null)
          Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13))),
        _heading('THE GOAL'),
        _pair(_text(_title, 'Goal *', hint: 'Apply to 40 internships'),
            _text(_target, 'Target *', kb: TextInputType.number)),
        _drop('What counts', d.metric, goalMetrics, (v) => setState(() => d.metric = v),
            labels: goalMetricLabel),
        if (d.metric == 'manual')
          const _Hint('You tap + on the goal each time you make progress.'),
        _heading('TIMEFRAME'),
        _pair(
          WhenField(label: 'Count from (blank = all time)', initial: d.since,
              onChanged: (v) => d.since = v),
          WhenField(label: 'Reach it by', initial: d.due, onChanged: (v) => d.due = v),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: const TextStyle(fontSize: 12.5, color: C.ink3)),
      );
}
