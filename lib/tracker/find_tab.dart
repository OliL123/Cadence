part of 'career_page.dart';

// ---------------- Find ----------------
//
// The job inbox: postings from SimplifyJobs and the companies you follow,
// filtered by your chips and ranked for you. Add moves one into
// Applications (To apply); Dismiss hides it and teaches the ranking.

class _FindTab extends StatefulWidget {
  final _CareerPageState page;
  const _FindTab(this.page);

  @override
  State<_FindTab> createState() => _FindTabState();
}

class _FindTabState extends State<_FindTab> {
  final _search = TextEditingController();
  String _query = '';
  bool? _showFilters; // null = decide by width the first time
  int _moreShown = 60; // companies shown under MORE MATCHES
  final _openCompanies = <String>{}; // companies whose extra roles are expanded

  FindService get svc => FindService.instance;

  @override
  void initState() {
    super.initState();
    svc.open();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setPrefs(void Function(FindPrefs p) change, {bool refetch = false}) {
    final p = FindPrefs.fromJson(store.findPrefs.toJson());
    change(p);
    store.setFindPrefs(p);
    if (refetch) {
      svc.refresh();
    } else {
      svc.checkSponsorship(); // newly matching postings may be unread
    }
  }

  static Color interestColor(String i) => switch (i) {
        'game' => C.red,
        'ml' => C.plum,
        'data' => C.teal,
        'quant' => C.mustard,
        'hardware' => C.olive,
        'product' => C.mustard,
        _ => C.navy,
      };

  /// The colour of a posting: its strongest interest you selected.
  Color _colorOf(Posting p) {
    final ints = interestsOf(p);
    for (final i in ['game', 'ml', 'swe', 'data', 'quant', 'hardware', 'product']) {
      if (ints.contains(i) && store.findPrefs.interests.contains(i)) return interestColor(i);
    }
    return interestColor(ints.first);
  }

  static String _ago(DateTime? d) {
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 14) return '${days}d ago';
    if (days < 60) return '${days ~/ 7}w ago';
    return '${days ~/ 30}mo ago';
  }

  String _where(Posting p) {
    final codes = p.countries.where((c) => c != 'OTHER').toList();
    final first = p.locations.isEmpty ? '' : p.locations.first;
    final more = p.locations.length > 1 ? ' +${p.locations.length - 1}' : '';
    return [
      if (first.isNotEmpty) '$first$more',
      if (codes.isNotEmpty && !first.toUpperCase().contains(codes.first)) codes.join('/'),
    ].join(' · ');
  }

  // ---- actions ----

  void _add(Posting p) {
    final a = store.addPosting(p);
    widget.page._snack('Added ${p.company} to To apply',
        undo: () => store.removeCareerItems([a.id], const []));
  }

  void _dismiss(Posting p) {
    store.dismissPosting(p);
    widget.page._snack('Dismissed — Find will rank roles like it lower',
        undo: () => store.undismissPosting(p.key));
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 760;
        final showFilters = _showFilters ?? wide;
        final prefs = store.findPrefs;
        final handled = store.handledPostingKeys;
        final links = store.applicationLinks;
        String roleKey(String co, String t) =>
            '${co.toLowerCase().trim()}|${t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()}';
        final haveRoles = {for (final a in store.applications) roleKey(a.company, a.role)};
        final taste = FindTaste.from(
          liked: store.applications.where((a) => a.from != 'import' || a.status != 'to-apply'),
          dismissed: store.findDismissed.values,
          pinned: store.careerPins,
        );
        final words =
            _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        final scored = <(Posting, int)>[
          for (final p in svc.postings)
            if (!handled.contains(p.key) &&
                !links.contains(p.url) &&
                !haveRoles.contains(roleKey(p.company, p.title)) &&
                findMatches(p, prefs) &&
                (words.isEmpty ||
                    words.every('${p.company} ${p.title} ${p.locations.join(' ')}'
                        .toLowerCase()
                        .contains)))
              (p, findScore(p, prefs, taste)),
        ]..sort((a, b) => b.$2 != a.$2
            ? b.$2.compareTo(a.$2)
            : (b.$1.posted ?? DateTime(2000)).compareTo(a.$1.posted ?? DateTime(2000)));

        // One entry per company, in the order of its best-ranked role; the
        // company's other roles travel with it (collapsed under its card)
        // instead of filling the grid with the same company again and again.
        final byCompany = <String, List<Posting>>{};
        for (final (p, _) in scored) {
          (byCompany[p.company.toLowerCase().trim()] ??= []).add(p);
        }
        final groups = byCompany.values.toList();
        final top = groups.take(12).toList();
        final fresh = groups.skip(12).where((g) => svc.isNew(g.first)).toList();
        final restAll = groups.skip(12).where((g) => !svc.isNew(g.first)).toList();
        final rest = restAll.take(_moreShown).toList();
        final restTotal = restAll.length;
        int roles(List<List<Posting>> gs) => gs.fold(0, (n, g) => n + g.length);

        final cols = (c.maxWidth / 300).floor().clamp(1, 6);
        final rows = <Widget Function()>[
          () => _toolbar(scored.length),
          if (showFilters) () => _filters(prefs) else () => _filterSummary(prefs),
          if (svc.postings.isEmpty && svc.loading)
            () => Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                      child: _none('Fetching postings from SimplifyJobs and '
                          '${prefs.boards.length} companies…')),
                ),
          if (svc.postings.isNotEmpty && scored.isEmpty)
            () => Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                      child: _none('Nothing new matches — widen the countries, interests or '
                          'dates, or follow more companies.')),
                ),
        ];
        void section(String title, Color color, List<List<Posting>> gs, {List<List<Posting>>? all}) {
          if (gs.isEmpty) return;
          final counted = all ?? gs;
          final n = roles(counted);
          rows.add(() => _sectionTitle(title,
              color: color,
              count: n == counted.length ? '$n' : '$n roles · ${counted.length} companies'));
          for (var i = 0; i < gs.length; i += cols) {
            final chunk = gs.sublist(i, i + cols > gs.length ? gs.length : i + cols);
            rows.add(() => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var k = 0; k < cols; k++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: k < cols - 1 ? 10 : 0),
                          child: k < chunk.length ? _group(chunk[k]) : const SizedBox.shrink(),
                        ),
                      ),
                  ]),
                ));
          }
        }

        section('TOP PICKS FOR YOU', C.red, top);
        section('NEW SINCE YOUR LAST VISIT', C.green, fresh);
        section('MORE MATCHES', C.ink3, rest, all: restAll);
        if (rest.length < restTotal) {
          rows.add(() => Center(
                child: TextButton(
                  onPressed: () => setState(() => _moreShown += 60),
                  child: Text('Show more (${restTotal - rest.length} more companies)'),
                ),
              ));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          itemCount: rows.length,
          itemBuilder: (_, i) => rows[i](),
        );
      }),
    );
  }

  Widget _toolbar(int matches) {
    final status = svc.loading
        ? 'Refreshing…'
        : svc.fetchedAt == null
            ? 'Not fetched yet'
            : 'Updated ${_ago(svc.fetchedAt)} · $matches matches';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 250,
          height: 34,
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 13, color: C.ink),
            decoration: InputDecoration(
              hintText: 'Search company, role, city…',
              hintStyle: const TextStyle(fontSize: 12.5, color: C.ink3),
              prefixIcon: const Icon(Icons.search, size: 18, color: C.ink3),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              isDense: true,
              filled: true,
              fillColor: C.paper,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: C.line, width: 1.4)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: const BorderSide(color: C.green, width: 1.6)),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: svc.loading ? null : svc.refresh,
          icon: svc.loading
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, size: 16),
          label: const Text('Refresh', style: TextStyle(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
              foregroundColor: C.greenD,
              side: const BorderSide(color: C.green, width: 1.4),
              minimumSize: const Size(0, 34)),
        ),
        OutlinedButton.icon(
          onPressed: _companiesDialog,
          icon: const Icon(Icons.business_outlined, size: 16),
          label: Text('Companies (${store.findPrefs.boards.length})',
              style: const TextStyle(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
              foregroundColor: C.navy,
              side: const BorderSide(color: C.navy, width: 1.4),
              minimumSize: const Size(0, 34)),
        ),
        Text(status, style: mono(size: 10.5, color: C.ink3)),
        if (svc.pendingChecks > 0)
          Tooltip(
            message: 'Reading job descriptions for what they say about visa sponsorship',
            child: Text('checking sponsorship · ${svc.pendingChecks} left',
                style: mono(size: 10.5, color: C.navy)),
          ),
        if (svc.errors.isNotEmpty)
          Tooltip(
            message: svc.errors.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            child: Text('${svc.errors.length} source${svc.errors.length == 1 ? '' : 's'} failed',
                style: mono(size: 10.5, color: C.red, w: FontWeight.w700)),
          ),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap, {Color color = C.green}) => Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: on ? color : C.paper,
              border: Border.all(color: on ? color : C.line, width: 1.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (on) ...[
                const Icon(Icons.check, size: 13, color: C.creamTxt),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: on ? C.creamTxt : C.ink2)),
            ]),
          ),
        ),
      );

  Widget _filterRow(String label, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(label, style: mono(size: 10, color: C.ink3, w: FontWeight.w700)),
            ),
          ),
          Expanded(child: Wrap(children: chips)),
        ]),
      );

  Widget _filters(FindPrefs prefs) {
    void toggle(List<String> list, String v) => list.contains(v) ? list.remove(v) : list.add(v);
    const ages = {14: '2 weeks', 30: '1 month', 60: '2 months', 0: 'Any time'};
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
      decoration: BoxDecoration(
        color: C.paper,
        border: Border.all(color: C.line, width: 1.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _filterRow('COUNTRIES', [
          for (final c in findCountries)
            _chip(findCountryLabel[c]!, prefs.countries.contains(c),
                () => _setPrefs((p) => toggle(p.countries, c))),
        ]),
        _filterRow('INTERESTS', [
          for (final i in findInterests)
            _chip(findInterestLabel[i]!, prefs.interests.contains(i),
                () => _setPrefs((p) => toggle(p.interests, i)),
                color: interestColor(i)),
        ]),
        _filterRow('POSTED', [
          for (final e in ages.entries)
            _chip(e.value, prefs.maxAgeDays == e.key,
                () => _setPrefs((p) => p.maxAgeDays = e.key),
                color: C.navy),
        ]),
        _filterRow('VISA', [
          _chip('Hide no-sponsorship / citizens-only', prefs.hideNoSponsor,
              () => _setPrefs((p) => p.hideNoSponsor = !p.hideNoSponsor),
              color: C.red),
        ]),
        _filterRow('SOURCES', [
          _chip('SimplifyJobs (US · CA · UK)', prefs.useSimplify,
              () => _setPrefs((p) => p.useSimplify = !p.useSimplify, refetch: true),
              color: C.teal),
          _chip('SpeedyApply (US + international)', prefs.lists.contains('speedyapply'),
              () => _setPrefs((p) => toggle(p.lists, 'speedyapply'), refetch: true),
              color: C.teal),
          _chip('vanshb03 list', prefs.lists.contains('vansh'),
              () => _setPrefs((p) => toggle(p.lists, 'vansh'), refetch: true),
              color: C.teal),
          _chip('Hide PhD/MBA-only', prefs.hideAdvancedDegree,
              () => _setPrefs((p) => p.hideAdvancedDegree = !p.hideAdvancedDegree, refetch: true),
              color: C.teal),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _showFilters = false),
            child: const Text('Hide filters', style: TextStyle(fontSize: 12)),
          ),
        ),
      ]),
    );
  }

  Widget _filterSummary(FindPrefs prefs) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: () => setState(() => _showFilters = true),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: C.paper,
              border: Border.all(color: C.line, width: 1.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.tune, size: 16, color: C.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    prefs.countries.join(' · '),
                    prefs.interests.map((i) => findInterestLabel[i]).join(', '),
                    prefs.maxAgeDays == 0 ? 'any time' : 'last ${prefs.maxAgeDays} days',
                    if (prefs.hideNoSponsor) 'hiding no-sponsorship',
                  ].join('  —  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: C.ink2),
                ),
              ),
              const Text('Edit', style: TextStyle(fontSize: 12, color: C.greenD, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  /// What the posting says about sponsorship, with the sentence on hover.
  Widget _sponsorMark(SponsorCheck s) => Tooltip(
        message: s.isWarning
            ? '${s.why}\n\nFor F-1 interns this often means no future H-1B; CPT may still be '
                'fine — worth checking before applying.'
            : s.why,
        child: s.isWarning
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, size: 13, color: C.red),
                const SizedBox(width: 2),
                _pill(sponsorLabel[s.flag]!, C.red, filled: true),
              ])
            : _pill(sponsorLabel[s.flag]!, C.green),
      );

  /// A company: its best role as a full card, and its other roles collapsed
  /// into a "+N more roles" bar that expands into compact rows.
  Widget _group(List<Posting> g) {
    if (g.length == 1) return _card(g.first);
    final key = g.first.company.toLowerCase().trim();
    final open = _openCompanies.contains(key);
    final color = _colorOf(g.first);
    final others = g.skip(1).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _card(g.first),
      // The bar tucks under the card like a stack of more cards.
      Transform.translate(
        offset: const Offset(0, -6),
        child: Material(
          color: color.withValues(alpha: .12),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
          child: InkWell(
            onTap: () => setState(() => open ? _openCompanies.remove(key) : _openCompanies.add(key)),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: color.withValues(alpha: .5)),
                  right: BorderSide(color: color.withValues(alpha: .5)),
                  bottom: BorderSide(color: color.withValues(alpha: .5)),
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
              ),
              child: Row(children: [
                Icon(Icons.layers_outlined, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    open
                        ? 'Hide ${others.length} more at ${g.first.company}'
                        : '+${others.length} more ${others.length == 1 ? 'role' : 'roles'} at ${g.first.company}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: color),
              ]),
            ),
          ),
        ),
      ),
      if (open)
        for (final p in others) _roleRow(p),
    ]);
  }

  /// One of a company's other roles, compact: title, where/when, Add, Dismiss.
  Widget _roleRow(Posting p) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: C.paper,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => csvio.openLink(p.url),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 7, 4, 7),
              decoration: BoxDecoration(
                border: Border.all(color: C.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(p.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600, color: C.ink, height: 1.25)),
                      ),
                      if (svc.isNew(p)) ...[
                        const SizedBox(width: 6),
                        _pill('NEW', C.green, filled: true),
                      ],
                      if (p.sponsor != null) ...[
                        const SizedBox(width: 6),
                        _sponsorMark(p.sponsor!),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _where(p),
                        p.deadline != null ? 'closes ${fmtWhen(p.deadline)}' : _ago(p.posted),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 10, color: p.deadline != null ? C.red : C.ink3),
                    ),
                  ]),
                ),
                IconButton(
                  tooltip: 'Add to Applications',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                  icon: const Icon(Icons.add_circle_outline, size: 20, color: C.green),
                  onPressed: () => _add(p),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                  icon: const Icon(Icons.close, size: 18, color: C.ink3),
                  onPressed: () => _dismiss(p),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _card(Posting p) {
    final color = _colorOf(p);
    final ints = interestsOf(p).where(store.findPrefs.interests.contains).toList();
    return _tile(
      color: color,
      height: 138,
      onTap: () => csvio.openLink(p.url),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _monogram(p.company, color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(p.company,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: C.ink, height: 1.2)),
                ),
                if (svc.isNew(p)) ...[
                  const SizedBox(width: 6),
                  _pill('NEW', C.green, filled: true),
                ],
              ]),
              const SizedBox(height: 2),
              Text(p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: C.ink2, height: 1.25)),
            ]),
          ),
          IconButton(
            tooltip: 'Add to Applications',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            icon: const Icon(Icons.add_circle_outline, size: 20, color: C.green),
            onPressed: () => _add(p),
          ),
          IconButton(
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            icon: const Icon(Icons.close, size: 18, color: C.ink3),
            onPressed: () => _dismiss(p),
          ),
        ]),
        const Spacer(),
        // Where · source, and when — plain text on its own line, so the tag
        // strip below never has to squeeze them.
        Row(children: [
          Expanded(
            child: Text(
              [_where(p), findSourceLabel[p.source] ?? p.source].where((x) => x.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(size: 10, color: C.ink2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 5),
            child: Text(
              p.deadline != null ? 'closes ${fmtWhen(p.deadline)}' : _ago(p.posted),
              style: mono(
                  size: 10,
                  color: p.deadline != null ? C.red : C.ink3,
                  w: p.deadline != null ? FontWeight.w700 : FontWeight.w400),
            ),
          ),
        ]),
        const SizedBox(height: 5),
        _tagStrip([
          if (p.sponsor != null) _sponsorMark(p.sponsor!),
          for (final i in ints)
            _pill(findInterestLabel[i]!.toUpperCase(), interestColor(i), filled: true),
        ]),
      ]),
    );
  }

  /// A row of tags that scrolls sideways when it doesn't fit (drag, swipe or
  /// shift-scroll), fading out at the right edge instead of being cut off.
  Widget _tagStrip(List<Widget> tags) {
    if (tags.isEmpty) return const SizedBox(height: 20);
    return SizedBox(
      height: 22,
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, .88, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ScrollConfiguration(
          // Let a mouse drag it too (Flutter only drags with touch by default).
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
            scrollbars: false,
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 24),
            children: [
              for (final t in tags)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Center(child: t),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- followed companies ----

  Future<void> _companiesDialog() async {
    final link = TextEditingController();
    var game = false;
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setD) {
        final prefs = store.findPrefs;
        final followed = {for (final b in prefs.boards) b.id};
        void save(List<FollowedBoard> boards) {
          _setPrefs((p) => p.boards = boards);
          setD(() {});
        }

        return AlertDialog(
          backgroundColor: C.paper2,
          title: const Text('Companies you follow'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                    'Find reads these companies\' own job boards for internships — the way to '
                    'reach game studios and Asia offices, which the lists barely cover. It can '
                    'follow Greenhouse, Lever, Ashby, SmartRecruiters and Workable boards.',
                    style: TextStyle(fontSize: 12.5, color: C.ink2)),
                const SizedBox(height: 10),
                Wrap(children: [
                  for (final b in prefs.boards)
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 6),
                      child: InputChip(
                        label: Text(b.name, style: const TextStyle(fontSize: 12)),
                        avatar: b.game ? const Icon(Icons.sports_esports, size: 15) : null,
                        onDeleted: () => save(prefs.boards.where((x) => x.id != b.id).toList()),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Text('SUGGESTED', style: mono(size: 10, color: C.ink3, w: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(children: [
                  for (final b in suggestedBoards)
                    if (!followed.contains(b.id))
                      Padding(
                        padding: const EdgeInsets.only(right: 6, bottom: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.add, size: 15),
                          label: Text(b.name, style: const TextStyle(fontSize: 12)),
                          onPressed: () => save([...prefs.boards, b]),
                        ),
                      ),
                ]),
                const SizedBox(height: 10),
                Text('ADD BY CAREERS LINK', style: mono(size: 10, color: C.ink3, w: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: link,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. boards.greenhouse.io/riotgames or jobs.smartrecruiters.com/Ubisoft2',
                    errorText: error,
                    errorMaxLines: 3,
                  ),
                ),
                Row(children: [
                  Checkbox(value: game, onChanged: (v) => setD(() => game = v ?? false)),
                  const Text('Game studio (all its roles count as game dev)',
                      style: TextStyle(fontSize: 12)),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setD(() {
                              busy = true;
                              error = null;
                            });
                            final (b, err) = await FindService.resolve(link.text.trim());
                            setD(() => busy = false);
                            if (b == null) {
                              setD(() => error = err);
                              return;
                            }
                            if (followed.contains(b.id)) {
                              setD(() => error = 'Already following ${b.name}.');
                              return;
                            }
                            link.clear();
                            save([...store.findPrefs.boards, FollowedBoard(b.ats, b.slug, b.name, game: game)]);
                          },
                    style: FilledButton.styleFrom(backgroundColor: C.green),
                    child: Text(busy ? 'Checking…' : 'Follow'),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Done')),
          ],
        );
      }),
    );
    link.dispose();
    svc.refresh();
  }
}
