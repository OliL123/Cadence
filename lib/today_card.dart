import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'palette.dart';

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

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
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

  (String, int) _nextHoliday(DateTime now) {
    final t0 = DateTime(now.year, now.month, now.day);
    final list = <(String, DateTime)>[
      ('元旦', DateTime(now.year, 1, 1)),
      ('春節', DateTime(2026, 2, 17)),
      ('清明', DateTime(now.year, 4, 5)),
      ('勞動節', DateTime(now.year, 5, 1)),
      ('中秋', DateTime(2026, 9, 25)),
      ('國慶', DateTime(now.year, 10, 1)),
      ('聖誕', DateTime(now.year, 12, 25)),
      ('元旦', DateTime(now.year + 1, 1, 1)),
    ];
    String name = '—';
    int best = 1 << 30;
    for (final h in list) {
      final d = h.$2.difference(t0).inDays;
      if (d >= 0 && d < best) {
        best = d;
        name = h.$1;
      }
    }
    return (name, best == (1 << 30) ? 0 : best);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final wd = ['日', '一', '二', '三', '四', '五', '六'][now.weekday % 7];
    String p(int n) => n.toString().padLeft(2, '0');
    final clock = '${p(now.hour)}:${p(now.minute)}:${p(now.second)}';
    final hol = _nextHoliday(now);

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
            Expanded(flex: 19, child: _infoCol(context, hol)),
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

  Widget _infoCol(BuildContext context, (String, int) hol) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _mini(Icons.wb_sunny_outlined, C.mustard, '天氣 WEATHER', '31° 天晴',
                  () => _showWeather(context)),
              const SizedBox(height: 12),
              _mini(Icons.celebration_outlined, C.red, '假期 HOLIDAY',
                  '${hol.$1} ${hol.$2}日', () => _showHolidays(context)),
            ]),
      );

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
                Text(label, style: _mono(8, C.ink3).copyWith(letterSpacing: .8)),
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

  void _showWeather(BuildContext context) => _sheet(
        context, '天氣', 'WEATHER', C.mustard, Icons.wb_sunny_outlined, [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('31°', style: _serif(40, C.ink)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('天晴 · Clear\nAnn Arbor', style: _sans(13, C.ink2)),
            ),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _fc('今', '31°', Icons.wb_sunny_outlined),
            _fc('明', '29°', Icons.cloud_outlined),
            _fc('三', '27°', Icons.grain),
            _fc('四', '30°', Icons.wb_sunny_outlined),
            _fc('五', '28°', Icons.cloud_outlined),
          ]),
          _demoNote('Sample forecast — the app will use your location for live weather.'),
        ]);

  Widget _fc(String day, String temp, IconData icon) => Column(children: [
        Text(day, style: _sans(12, C.ink2)),
        const SizedBox(height: 4),
        Icon(icon, size: 20, color: C.mustard),
        const SizedBox(height: 4),
        Text(temp, style: _mono(12, C.ink)),
      ]);

  void _showHolidays(BuildContext context) {
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final list = <(String, DateTime)>[
      ('中秋節', DateTime(2026, 9, 25)),
      ('國慶日', DateTime(now.year, 10, 1)),
      ('重陽節', DateTime(2026, 10, 19)),
      ('聖誕節', DateTime(now.year, 12, 25)),
      ('元旦', DateTime(now.year + 1, 1, 1)),
      ('農曆新年', DateTime(2027, 2, 6)),
    ];
    final upcoming = list.where((h) => !h.$2.isBefore(t0)).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    _sheet(context, '假期', 'HOLIDAYS', C.red, Icons.celebration_outlined, [
      for (final h in upcoming.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(children: [
            Expanded(child: Text(h.$1, style: _sans(14, C.ink, FontWeight.w700))),
            Text('${h.$2.year}/${h.$2.month}/${h.$2.day}', style: _mono(11, C.ink3)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(5)),
              child: Text('${h.$2.difference(t0).inDays}日',
                  style: _mono(10.5, C.creamTxt).copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      _demoNote('Hong Kong public holidays.'),
    ]);
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
