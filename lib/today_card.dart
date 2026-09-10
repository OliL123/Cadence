import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'palette.dart';
import 'services.dart';
import 'store.dart';
import 'calendar/gcal.dart';
import 'hoverable.dart';

TextStyle _serif(double s, Color c) =>
    GoogleFonts.notoSerifHk(fontWeight: FontWeight.w900, fontSize: s, color: c);
TextStyle _sans(double s, Color c, [FontWeight w = FontWeight.w700]) =>
    GoogleFonts.notoSansHk(fontSize: s, color: c, fontWeight: w);
TextStyle _mono(double s, Color c) =>
    GoogleFonts.spaceMono(fontSize: s, color: c, fontWeight: FontWeight.w700);

class TodayCard extends StatefulWidget {
  const TodayCard({super.key});
  @override
  State<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<TodayCard> {
  Timer? _timer;
  WeatherData? _wx;
  bool _wxLoading = true;
  List<Holiday> _holidays = [];
  bool _holLoading = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadWeather();
    _loadHolidays();
  }

  Future<void> _loadWeather() async {
    if (mounted) setState(() => _wxLoading = true);
    final w = await fetchWeather(store.weatherLat, store.weatherLon);
    if (mounted) setState(() { _wx = w; _wxLoading = false; });
  }

  Future<void> _loadHolidays() async {
    if (mounted) setState(() => _holLoading = true);
    final now = DateTime.now();
    final all = <Holiday>[];
    for (final c in store.holidayCountries) {
      all.addAll(await fetchHolidays(c, now.year));
      all.addAll(await fetchHolidays(c, now.year + 1));
    }
    if (mounted) setState(() { _holidays = all; _holLoading = false; });
  }

  Holiday? _nextHoliday() {
    final t0 = DateTime.now();
    final t = DateTime(t0.year, t0.month, t0.day);
    final upcoming = _holidays.where((h) => !h.date.isBefore(t)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _ganzhi(int y) {
    const stems = '甲乙丙丁戊己庚辛壬癸';
    const branches = '子丑寅卯辰巳午未申酉戌亥';
    final i = ((y - 4) % 10 + 10) % 10;
    final j = ((y - 4) % 12 + 12) % 12;
    return '${stems[i]}${branches[j]}年';
  }

  String _zodiac(int y) {
    const zod = '鼠牛虎兔龍蛇馬羊猴雞狗豬';
    final j = ((y - 4) % 12 + 12) % 12;
    return '${zod[j]}年';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final wd = ['日', '一', '二', '三', '四', '五', '六'][now.weekday % 7];
    String p(int n) => n.toString().padLeft(2, '0');
    final clock = '${p(now.hour)}:${p(now.minute)}:${p(now.second)}';

    return _enamel(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // header bar
        Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: C.red, width: 2))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration:
                  BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(5)),
              child: Text('今日 TODAY', style: _serif(12, C.creamTxt)),
            ),
            const Spacer(),
            Text('星期$wd', style: _serif(14, C.red)),
            const SizedBox(width: 9),
            Text(clock,
                style: _mono(13, C.red)
                    .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        // three columns side-by-side on wide, stacked on narrow
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 440) {
            return Column(children: [
              _dateCol(now, center: true),
              _hdiv(),
              _infoCol(context),
              _hdiv(),
              _calCol(context),
            ]);
          }
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 22, child: _dateCol(now)),
              _vdiv(),
              Expanded(flex: 23, child: _infoCol(context)),
              _vdiv(),
              Expanded(flex: 20, child: _calCol(context)),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _vdiv() => Container(width: 2, color: C.red);
  Widget _hdiv() => Container(height: 2, color: C.red);

  Widget _dateCol(DateTime now, {bool center = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        child: Column(
            crossAxisAlignment:
                center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
          Text('${now.year}年${now.month}月${now.day}日', style: _serif(18, C.red)),
          const SizedBox(height: 3),
          Text('${_ganzhi(now.year)} · ${_zodiac(now.year)}', style: _sans(11.5, C.ink2)),
          const SizedBox(height: 10),
          RichText(
            textAlign: center ? TextAlign.center : TextAlign.start,
            text: TextSpan(children: [
              TextSpan(text: '宜 開工', style: _sans(12, C.greenD)),
              TextSpan(text: '  ·  ', style: _sans(12, C.ink3)),
              TextSpan(text: '忌 拖延', style: _sans(12, C.red)),
            ]),
          ),
        ]),
      );

  int _daysTo(DateTime d) => DateTime(d.year, d.month, d.day)
      .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
      .inDays;


  Widget _infoCol(BuildContext context) {
    final wxIcon = _wx == null ? Icons.wb_sunny_outlined : weatherInfo(_wx!.code).$2;
    final wxVal = _wxLoading
        ? 'loading…'
        : (_wx == null
            ? 'tap to set'
            : '${_wx!.temp.round()}° ${weatherInfo(_wx!.code).$1}');
    final h = _nextHoliday();
    final holName = _holLoading ? 'loading…' : (h == null ? 'none found' : h.name);
    final holDays = h == null ? null : _daysTo(h.date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _mini(wxIcon, C.mustard, '天氣 ${store.weatherPlace.toUpperCase()}', wxVal,
                () => _showWeather(context)),
            const SizedBox(height: 6),
            _holidayRow(
                context,
                h == null ? C.red : placeColor(h.country),
                '假期 ${store.holidayCountries.join(' · ')}',
                holName,
                holDays),
          ]),
    );
  }

  /// The "next holiday" row: a compact day-count badge sits before the holiday
  /// name so the number is clearly a countdown to that named holiday.
  Widget _holidayRow(
          BuildContext context, Color color, String label, String name, int? days) =>
      InkWell(
        onTap: () => _showHolidays(context),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(Icons.celebration_outlined, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$label · NEXT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mono(8, C.ink3).copyWith(letterSpacing: .8)),
                Row(children: [
                  if (days != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration:
                          BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
                      child: Text(_hdaysShort(days),
                          style: _mono(9.5, Colors.white).copyWith(letterSpacing: .2)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(12.5, C.ink)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 15, color: C.ink3),
          ]),
        ),
      );

  /// Compact countdown for the badge: "today" / "tmr" / "24d".
  String _hdaysShort(int d) => d == 0 ? 'today' : (d == 1 ? 'tmr' : '${d}d');

  Widget _mini(IconData icon, Color ic, String label, String value, VoidCallback onTap,
          {Widget? trailing}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(icon, size: 18, color: ic),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _mono(8, C.ink3).copyWith(letterSpacing: .8)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(12.5, C.ink)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 15, color: C.ink3),
          ]),
        ),
      );

  Widget _calCol(BuildContext context) => ListenableBuilder(
        listenable: GCalService.instance,
        builder: (context, _) {
          final g = GCalService.instance;
          return Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('行事曆 CALENDAR', style: _mono(8, C.ink3).copyWith(letterSpacing: .6)),
                const Spacer(),
                if (g.isConnected)
                  InkWell(
                    onTap: () => _showCalendar(context),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.tune, size: 14, color: C.navy),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                        border: Border.all(color: C.mustard),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('示範', style: _mono(7.5, C.mustard)),
                  ),
              ]),
              const SizedBox(height: 5),
              ..._calBody(context, g),
            ]),
          );
        },
      );

  List<Widget> _calBody(BuildContext context, GCalService g) {
    // Mobile / unsupported: keep the sample rows (calendar is web-only for now).
    if (!g.supported) {
      return [
        _calSample(Icons.cake_outlined, "May's birthday", 'today'),
        _calSample(Icons.push_pin_outlined, 'Dentist', '3pm'),
        const SizedBox(height: 4),
        Text('Link Google Calendar in the web app',
            style: _sans(10, C.ink3, FontWeight.w500)),
      ];
    }
    if (g.isConnected) {
      final ev = g.events;
      if (ev.isEmpty) {
        return [
          Text('No upcoming events', style: _sans(12, C.ink2)),
          const SizedBox(height: 4),
          Text('Tap ⋯ to pick calendars', style: _sans(10, C.ink3, FontWeight.w500)),
        ];
      }
      return [
        for (final e in ev.take(3)) _calEventItem(context, e),
      ];
    }
    // idle / connecting / error
    return [
      if (g.stage == GCalStage.error && g.message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(g.message!, style: _sans(11, C.red, FontWeight.w500)),
        ),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: g.isBusy ? null : () => g.connect(),
          icon: g.isBusy
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: C.navy))
              : const Icon(Icons.link, size: 14),
          label: Text(g.isBusy ? 'Connecting…' : 'Connect Google', style: _sans(11, C.navy)),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.navy,
            side: const BorderSide(color: C.navy, width: 1.3),
            padding: const EdgeInsets.symmetric(vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ),
    ];
  }

  Widget _calSample(IconData icon, String name, String when) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 14, color: C.ink2),
          const SizedBox(width: 7),
          Expanded(
              child: Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(12, C.ink, FontWeight.w600))),
          Text(when, style: _mono(9.5, C.ink3)),
        ]),
      );

  Widget _calEventItem(BuildContext context, GCalEvent e) => InkWell(
        onTap: () => _showCalendar(context),
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(e.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(12, C.ink, FontWeight.w600))),
            const SizedBox(width: 6),
            Text(_evWhen(e), style: _mono(9.5, C.ink3)),
          ]),
        ),
      );

  /// Compact "when" label for an event: today/tmr/weekday/date + time.
  String _evWhen(GCalEvent e) {
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final d0 = DateTime(e.start.year, e.start.month, e.start.day);
    final days = d0.difference(t0).inDays;
    String day;
    if (days == 0) {
      day = 'today';
    } else if (days == 1) {
      day = 'tmr';
    } else if (days > 1 && days < 7) {
      day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][e.start.weekday % 7];
    } else {
      const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      day = '${e.start.day} ${mon[e.start.month - 1]}';
    }
    if (e.allDay) return day;
    final h = e.start.hour;
    final m = e.start.minute.toString().padLeft(2, '0');
    final ap = h < 12 ? 'a' : 'p';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final time = m == '00' ? '$h12$ap' : '$h12:$m$ap';
    return days == 0 ? time : '$day $time';
  }

  // ---------------- detail sheets ----------------
  void _sheet(BuildContext context, String zh, String en, Color color,
      IconData icon, List<Widget> body) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.paper2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 26 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 10),
              Text(zh, style: _serif(20, color)),
              const SizedBox(width: 8),
              Text(en, style: _mono(11, C.ink3).copyWith(letterSpacing: 1)),
              const Spacer(),
              _sheetClose(ctx),
            ]),
            const SizedBox(height: 14),
            ...body,
          ]),
        ),
      ),
    );
  }

  /// A close button so any detail sheet can be dismissed even on a tiny/fold
  /// screen where there's no scrim left to tap.
  Widget _sheetClose(BuildContext ctx) => InkWell(
        onTap: () => Navigator.of(ctx).maybePop(),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: C.paper,
            border: Border.all(color: C.line),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 16, color: C.ink2),
        ),
      );


  void _showWeather(BuildContext context) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    _sheet(context, '天氣', store.weatherPlace.toUpperCase(), C.mustard,
        _wx == null ? Icons.wb_sunny_outlined : weatherInfo(_wx!.code).$2, [
      if (_wxLoading)
        Text('Loading…', style: _sans(13, C.ink2))
      else if (_wx == null)
        Text('Could not load weather. Set a location below.', style: _sans(13, C.ink2))
      else ...[
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_wx!.temp.round()}°', style: _serif(40, C.ink)),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${weatherInfo(_wx!.code).$1}\n${store.weatherPlace}',
                style: _sans(13, C.ink2)),
          ),
        ]),
        if (_wx!.hours.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('稍後 · LATER TODAY', style: _mono(9, C.ink3).copyWith(letterSpacing: 1)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final h in _wx!.hours.take(24))
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _hourTile(h),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        Text('未來五日 · 5-DAY', style: _mono(9, C.ink3).copyWith(letterSpacing: 1)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final d in _wx!.days.take(5))
            _fc(wd[d.date.weekday - 1], '${d.max.round()}°', weatherInfo(d.code).$2),
        ]),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _pickLocation(context);
          },
          icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
          label: const Text('Change location'),
          style: OutlinedButton.styleFrom(
              foregroundColor: C.navy, side: const BorderSide(color: C.navy)),
        ),
      ),
    ]);
  }

  void _pickLocation(BuildContext context) {
    final ctl = TextEditingController(text: store.weatherPlace);
    List<GeoPlace> results = [];
    bool searching = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: C.paper2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> search() async {
          setLocal(() => searching = true);
          final r = await geocode(ctl.text);
          setLocal(() { results = r; searching = false; });
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Set weather location', style: _serif(17, C.red)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: ctl,
                  autofocus: true,
                  onSubmitted: (_) => search(),
                  decoration: const InputDecoration(
                    hintText: 'City name',
                    isDense: true,
                    filled: true,
                    fillColor: C.paper,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: search,
                style: FilledButton.styleFrom(backgroundColor: C.navy),
                child: const Text('Search'),
              ),
            ]),
            const SizedBox(height: 10),
            if (searching)
              const Padding(padding: EdgeInsets.all(8), child: Text('Searching…'))
            else
              for (final p in results)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name, style: _sans(14, C.ink)),
                  subtitle: Text(p.admin, style: _sans(11.5, C.ink3, FontWeight.w400)),
                  onTap: () {
                    store.setWeatherLocation(p.name, p.lat, p.lon);
                    _loadWeather();
                    Navigator.pop(ctx);
                  },
                ),
            const SizedBox(height: 6),
          ]),
        );
      }),
    );
  }

  Widget _fc(String day, String temp, IconData icon) => Column(children: [
        Text(day, style: _sans(12, C.ink2)),
        const SizedBox(height: 4),
        Icon(icon, size: 20, color: C.mustard),
        const SizedBox(height: 4),
        Text(temp, style: _mono(12, C.ink)),
      ]);

  Widget _hourTile(HourForecast h) {
    final now = DateTime.now();
    final label = (h.time.year == now.year && h.time.month == now.month &&
            h.time.day == now.day && h.time.hour == now.hour)
        ? 'now'
        : (h.time.hour % 12 == 0 ? 12 : h.time.hour % 12).toString() +
            (h.time.hour < 12 ? 'a' : 'p');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: _mono(10, C.ink3)),
      const SizedBox(height: 6),
      Icon(weatherInfo(h.code).$2, size: 18, color: C.mustard),
      const SizedBox(height: 6),
      Text('${h.temp.round()}°', style: _mono(12, C.ink)),
    ]);
  }

  Widget _regionChip(String code, String label, bool on, VoidCallback onTap) {
    final col = placeColor(code);
    return Hoverable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      hoverColor: on ? const Color(0x26FFFFFF) : const Color(0x1F000000),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: on ? col : C.paper,
          border: Border.all(color: col, width: 1.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (on) ...[
            const Icon(Icons.check, size: 13, color: C.creamTxt),
            const SizedBox(width: 4),
          ],
          Text(label, style: _sans(12, on ? C.creamTxt : col, FontWeight.w700)),
        ]),
      ),
    );
  }

  void _showHolidays(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.paper2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final now = DateTime.now();
        final t0 = DateTime(now.year, now.month, now.day);
        final upcoming = _holidays.where((h) => !h.date.isBefore(t0)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.celebration_outlined, size: 22, color: C.red),
              const SizedBox(width: 10),
              Text('假期', style: _serif(20, C.red)),
              const SizedBox(width: 8),
              Text('HOLIDAYS', style: _mono(11, C.ink3).copyWith(letterSpacing: 1)),
            ]),
            const SizedBox(height: 14),
            if (upcoming.isNotEmpty)
              Builder(builder: (_) {
                final next = upcoming.first;
                final days = next.date.difference(t0).inDays;
                final col = placeColor(next.country);
                const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: .10),
                    border: Border.all(color: col, width: 1.4),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(children: [
                    Column(children: [
                      Text('${days == 0 ? 'TODAY' : days}',
                          style: _serif(days == 0 ? 22 : 34, col).copyWith(height: 1)),
                      if (days != 0) Text(days == 1 ? 'day' : 'days', style: _mono(9, col)),
                    ]),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(days == 0 ? 'today is' : 'until', style: _sans(11, C.ink3, FontWeight.w400)),
                        Text(next.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: _sans(15.5, C.ink)),
                        Text('${next.date.day} ${mon[next.date.month - 1]} · ${holidayPlaces[next.country] ?? next.country}',
                            style: _mono(10.5, C.ink3)),
                      ]),
                    ),
                  ]),
                );
              }),
            Text('Tap regions to show their holidays:', style: _sans(11.5, C.ink2)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in holidayPlaces.entries)
                _regionChip(e.key, e.value, store.holidayCountries.contains(e.key), () async {
                  store.toggleHolidayCountry(e.key);
                  setLocal(() {});
                  await _loadHolidays();
                  setLocal(() {});
                }),
            ]),
            const SizedBox(height: 14),
            if (_holLoading)
              Text('Loading…', style: _sans(13, C.ink2))
            else if (store.holidayCountries.isEmpty)
              Text('Pick at least one region above.', style: _sans(13, C.ink2))
            else if (upcoming.isEmpty)
              Text('No upcoming public holidays found.', style: _sans(13, C.ink2))
            else
              for (final h in upcoming.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(children: [
                    Container(
                      width: 9, height: 9, margin: const EdgeInsets.only(right: 9),
                      decoration: BoxDecoration(color: placeColor(h.country), borderRadius: BorderRadius.circular(2)),
                    ),
                    Expanded(child: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(14, C.ink, FontWeight.w700))),
                    Text('${h.date.year}/${h.date.month}/${h.date.day}', style: _mono(11, C.ink3)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: placeColor(h.country), borderRadius: BorderRadius.circular(5)),
                      child: Text('${h.date.difference(t0).inDays}d',
                          style: _mono(10.5, C.creamTxt).copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
          ]),
        );
      }),
    );
  }

  void _showCalendar(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.paper2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ListenableBuilder(
        listenable: GCalService.instance,
        builder: (context, _) {
          final g = GCalService.instance;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.event_outlined, size: 22, color: C.navy),
                    const SizedBox(width: 10),
                    Text('行事曆', style: _serif(20, C.navy)),
                    const SizedBox(width: 8),
                    Text('CALENDAR', style: _mono(11, C.ink3).copyWith(letterSpacing: 1)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => g.disconnect(),
                      style: TextButton.styleFrom(
                          foregroundColor: C.red, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: Text('Disconnect', style: _sans(12, C.red)),
                    ),
                    const SizedBox(width: 4),
                    _sheetClose(context),
                  ]),
                  const SizedBox(height: 6),
                  // ---- sub-calendar picker ----
                  Text('SHOW THESE CALENDARS',
                      style: _mono(9, C.ink3).copyWith(letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in g.calendars)
                        _calChip(c, g.isSelected(c.id), () => g.toggleCalendar(c.id)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('UPCOMING', style: _mono(9, C.ink3).copyWith(letterSpacing: 1)),
                  const SizedBox(height: 8),
                  if (g.events.isEmpty)
                    Text('Nothing in the next three weeks.', style: _sans(13, C.ink2))
                  else
                    for (final e in g.events) _calFullItem(e),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _calChip(GCalCalendar c, bool on, VoidCallback onTap) => Hoverable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: on ? const Color(0x26FFFFFF) : const Color(0x1F000000),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.color : C.paper,
            border: Border.all(color: c.color, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.check : Icons.circle_outlined,
                size: 13, color: on ? Colors.white : c.color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(c.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(12.5, on ? Colors.white : C.ink)),
            ),
          ]),
        ),
      );

  Widget _calFullItem(GCalEvent e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(14, C.ink, FontWeight.w600))),
          const SizedBox(width: 10),
          Text(_evWhen(e), style: _mono(11, C.ink2)),
        ]),
      );

  Widget _enamel({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: C.paper2,
          border: Border.all(color: C.red, width: 2),
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [BoxShadow(color: Color(0x22462D0F), offset: Offset(2, 2))],
        ),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            border: Border.all(color: C.red.withValues(alpha: .45), width: 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
        ),
      );
}
