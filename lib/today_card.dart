import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'palette.dart';
import 'services.dart';
import 'store.dart';

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
        // three columns
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 22, child: _dateCol(now)),
            _vdiv(),
            Expanded(flex: 19, child: _infoCol(context)),
            _vdiv(),
            Expanded(flex: 24, child: _calCol(context)),
          ]),
        ),
      ]),
    );
  }

  Widget _vdiv() => Container(width: 2, color: C.red);

  Widget _dateCol(DateTime now) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${now.year}年${now.month}月${now.day}日', style: _serif(18, C.red)),
          const SizedBox(height: 3),
          Text('${_ganzhi(now.year)} · ${_zodiac(now.year)}', style: _sans(11.5, C.ink2)),
          const Spacer(),
          const SizedBox(height: 8),
          RichText(
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
    final holVal = _holLoading
        ? 'loading…'
        : (h == null ? 'none found' : '${h.name} · ${_daysTo(h.date)}d');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _mini(wxIcon, C.mustard, '天氣 ${store.weatherPlace.toUpperCase()}', wxVal,
                () => _showWeather(context)),
            const SizedBox(height: 12),
            _mini(
                Icons.celebration_outlined,
                h == null ? C.red : placeColor(h.country),
                '假期 ${store.holidayCountries.join(' · ')}',
                holVal,
                () => _showHolidays(context)),
          ]),
    );
  }

  Widget _mini(IconData icon, Color ic, String label, String value, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: ic),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _mono(8, C.ink3).copyWith(letterSpacing: .8)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(12.5, C.ink)),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 15, color: C.ink3),
          ]),
        ),
      );

  Widget _calCol(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('行事曆 CALENDAR', style: _mono(8, C.ink3).copyWith(letterSpacing: .6)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  border: Border.all(color: C.mustard), borderRadius: BorderRadius.circular(4)),
              child: Text('示範', style: _mono(7.5, C.mustard)),
            ),
          ]),
          const SizedBox(height: 5),
          _calItem(context, Icons.cake_outlined, "May's birthday", 'today'),
          _calItem(context, Icons.push_pin_outlined, 'Dentist', '3pm'),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Demo — the real app connects Google Calendar'),
                    duration: Duration(seconds: 2)),
              ),
              icon: const Icon(Icons.link, size: 14),
              label: Text('Connect Google', style: _sans(11, C.navy)),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.navy,
                side: const BorderSide(color: C.navy, width: 1.3),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
        ]),
      );

  Widget _calItem(BuildContext context, IconData icon, String name, String when) => InkWell(
        onTap: () => _showCalItem(context, icon, name, when),
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(icon, size: 14, color: C.ink2),
            const SizedBox(width: 7),
            Expanded(
                child: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(12, C.ink, FontWeight.w600))),
            Text(when, style: _mono(9.5, C.ink3)),
          ]),
        ),
      );

  // ---------------- detail sheets ----------------
  void _sheet(BuildContext context, String zh, String en, Color color,
      IconData icon, List<Widget> body) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.paper2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 10),
            Text(zh, style: _serif(20, color)),
            const SizedBox(width: 8),
            Text(en, style: _mono(11, C.ink3).copyWith(letterSpacing: 1)),
          ]),
          const SizedBox(height: 14),
          ...body,
        ]),
      ),
    );
  }

  Widget _demoNote(String text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                border: Border.all(color: C.mustard), borderRadius: BorderRadius.circular(4)),
            child: Text('示範 DEMO', style: _mono(8, C.mustard)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: _sans(11.5, C.ink2))),
        ]),
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
        const SizedBox(height: 16),
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

  Widget _regionChip(String code, String label, bool on, VoidCallback onTap) {
    final col = placeColor(code);
    return GestureDetector(
      onTap: onTap,
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
            const SizedBox(height: 10),
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

  void _showCalItem(BuildContext context, IconData icon, String name, String when) => _sheet(
        context, '行事曆', 'EVENT', C.navy, icon, [
          Text(name, style: _serif(20, C.ink)),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.schedule, size: 15, color: C.ink3),
            const SizedBox(width: 6),
            Text(when, style: _sans(13, C.ink2)),
          ]),
          _demoNote('Sample event — connect Google Calendar to see your real birthdays & events here.'),
        ]);

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
