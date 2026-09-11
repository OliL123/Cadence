import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'palette.dart';
import 'labels.dart';
import 'models.dart';
import 'store.dart';
import 'hoverable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'today_card.dart';
import 'mahjong_page.dart';
import 'spread_wall.dart';
import 'chronicle.dart';
import 'home_widget_bridge.dart';
import 'supabase_config.dart';
import 'sync.dart';
import 'calendar/gcal.dart';
import 'notifications.dart';
import 'platform/apk_download_stub.dart'
    if (dart.library.html) 'platform/apk_download_web.dart' as apk;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  await initHomeWidget();
  Reminders.instance.init();
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    SyncService.instance.start();
  } catch (_) {
    // sync unavailable (offline / config) — app still works locally
  }
  // Google Calendar (web): silently reconnects if the user linked it before.
  GCalService.instance.init();
  runApp(const CadenceApp());
}

class CadenceApp extends StatelessWidget {
  const CadenceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: C.chronicle ? 'Chronicle' : 'Cadence',
      debugShowCheckedModeBanner: false,
      // en-GB so date pickers read/enter as DD/MM/YYYY.
      locale: const Locale('en', 'GB'),
      supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: C.paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: C.red,
          primary: C.red,
          surface: C.paper2,
          brightness: Brightness.light,
        ),
        textTheme: C.chronicle
            ? GoogleFonts.ebGaramondTextTheme()
            : GoogleFonts.hankenGroteskTextTheme(),
        popupMenuTheme: PopupMenuThemeData(
          color: C.paper2,
          elevation: 8,
          shadowColor: const Color(0x33462D0F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: const BorderSide(color: C.line, width: 1.2),
          ),
          textStyle: const TextStyle(color: C.ink, fontSize: 13),
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// A styled row (icon + label) for popup-menu items.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  const _MenuRow(this.icon, this.label, {this.danger = false});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 17, color: danger ? C.red : C.ink2),
        const SizedBox(width: 11),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: danger ? C.red : C.ink)),
      ]);
}

// shared type styles — each resolves to the active skin's font at build time.
//  Cadence: Noto Serif HK (accent) / Oswald (display) / Space Mono (labels).
//  Chronicle: Playfair Display (accent + display) / EB Garamond (labels).
TextStyle serifHk({double size = 14, Color color = C.ink}) => C.chronicle
    ? GoogleFonts.cinzel(fontWeight: FontWeight.w600, fontSize: size, color: color)
    : GoogleFonts.notoSerifHk(fontWeight: FontWeight.w900, fontSize: size, color: color);
TextStyle disp({double size = 14, FontWeight w = FontWeight.w600, Color color = C.ink}) =>
    C.chronicle
        ? GoogleFonts.cinzel(fontSize: size, fontWeight: w, color: color)
        : GoogleFonts.oswald(fontSize: size, fontWeight: w, color: color);
TextStyle mono({double size = 11, Color color = C.ink3, FontWeight w = FontWeight.w400}) =>
    C.chronicle
        ? GoogleFonts.ebGaramond(fontSize: size, color: color, fontWeight: w)
        : GoogleFonts.spaceMono(fontSize: size, color: color, fontWeight: w);

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _addCtl = TextEditingController();
  final _boardCtl = ScrollController();
  String _addGroup = store.groups.first.key;
  String _mobileView = 'tasks'; // mobile bottom-nav: 'tasks' or 'focus'
  DateTime? _addDate;
  int? _editingTaskId;
  int? _highlightId; // task briefly highlighted after a widget tap
  final _editCtl = TextEditingController();
  static const _widgetChannel = MethodChannel('cadence/widget');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Jump to a task the home-screen widget was tapped on.
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openTask' && call.arguments is int) {
        _openTask(call.arguments as int);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final id = await _widgetChannel.invokeMethod<int>('consumeLaunchTask');
        if (id != null) _openTask(id);
      } catch (_) {}
    });
  }

  /// Bring a task into view (from a widget tap): switch to the tasks page,
  /// reveal its group (or the Done archive), and flash it.
  void _openTask(int id) {
    final t = store.byId(id);
    if (t == null) return;
    setState(() {
      _mobileView = 'tasks';
      if (t.done) {
        store.setShowDone(true);
        store.setFilter('all');
      } else if (!t.daily) {
        store.setFilter(t.group);
      }
      _highlightId = id;
    });
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted && _highlightId == id) setState(() => _highlightId = null);
    });
  }

  void _snack(String msg, VoidCallback onUndo) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: C.greenD,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      showCloseIcon: true,
      closeIconColor: C.creamTxt,
      action: SnackBarAction(label: 'UNDO', textColor: C.mustard, onPressed: onUndo),
    ));
  }

  void _completeWithUndo(Task t) {
    final wasDone = t.done;
    store.toggleDone(t);
    if (!wasDone && t.done) _snack('✓ Completed', () => store.toggleDone(t));
  }

  void _deleteWithUndo(Task t) {
    final idx = store.tasks.indexOf(t);
    store.deleteTask(t);
    _snack('Task deleted', () => store.insertTask(t, idx < 0 ? 0 : idx));
  }

  void _pushToTomorrow(Task t) {
    final now = DateTime.now();
    store.setDue(t, DateTime(now.year, now.month, now.day + 1));
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 10) return 'just now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A home-screen widget tap may have changed the data on disk while we were
    // backgrounded — reload it and sync when we come back.
    if (state == AppLifecycleState.resumed) {
      SyncService.instance.onResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addCtl.dispose();
    _boardCtl.dispose();
    _editCtl.dispose();
    super.dispose();
  }

  void _startEditTitle(Task t) {
    setState(() {
      _editingTaskId = t.id;
      _editCtl.text = t.title;
      _editCtl.selection =
          TextSelection(baseOffset: 0, extentOffset: t.title.length);
    });
  }

  void _commitEditTitle(Task t) {
    if (_editingTaskId != t.id) return;
    final v = _editCtl.text.trim();
    if (v.isNotEmpty && v != t.title) store.setTitle(t, v);
    setState(() => _editingTaskId = null);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1040;
    final content = SafeArea(
      bottom: wide, // on mobile the bottom nav handles the inset
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (!store.groups.any((g) => g.key == _addGroup)) {
            _addGroup = store.groups.first.key;
          }
          if (wide) return _wideLayout();
          // Mobile: tasks and the mahjong wall are separate bottom-nav pages.
          return _mobileView == 'focus'
              ? _focusPage()
              : _stackedLayout(MediaQuery.of(context).size.width);
        },
      ),
    );
    return Scaffold(
      backgroundColor: C.chronicle ? Colors.transparent : null,
      // Chronicle: a continuously-fading marble ground with contour temple
      // columns framing the page edges, behind the content.
      body: C.chronicle
          ? ChronGround(
              child: Stack(children: [Positioned.fill(child: content), const ChronColumns()]),
            )
          : content,
      bottomNavigationBar: wide ? null : _mobileNav(),
    );
  }

  // ---------------- layouts ----------------
  /// Single scrolling column for tablets, phones, and foldable/flip cover
  /// screens (fluid down to ~280px). Everything present, just stacked.
  Widget _stackedLayout(double w) {
    final compact = w < 560; // phone
    final pad = compact ? 10.0 : 16.0;
    // Chronicle: transparent so the marble ground shows, and extra side padding
    // so the content clears the edge columns.
    final side = C.chronicle ? 52.0 : pad;
    return Container(
      color: C.chronicle ? Colors.transparent : C.paper2,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(side, pad, side, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!store.headerCollapsed) ...[
            _masthead(),
            const SizedBox(height: 12),
            const TodayCard(),
            const SizedBox(height: 8),
          ],
          _headerCollapseBar(),
          const SizedBox(height: 12),
          _enamel(
            edge: C.green,
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Column(children: [
                _tasksHeader(),
                _dueSoonBanner(),
                _groupChips(),
                const SizedBox(height: 4),
                if (store.viewMode == 'board')
                  SizedBox(height: 420, child: _boardView())
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Column(children: [
                      ..._dailySection(),
                      for (final g in _groupsToShow()) ..._section(g),
                      _addGroupTile(),
                      if (store.showDone) ...[
                        const SizedBox(height: 12),
                        ..._doneSection(),
                      ],
                    ]),
                  ),
                _addBar(),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// A slim strip that collapses/expands the masthead + TODAY card, so the
  /// task list can take the whole screen when the header isn't needed. When
  /// collapsed it still shows the app name, so you know where you are.
  Widget _headerCollapseBar() {
    final collapsed = store.headerCollapsed;
    return Hoverable(
      onTap: () => store.setHeaderCollapsed(!collapsed),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: C.chronicle ? C.paper2.withValues(alpha: .55) : C.paper2,
          border: Border.all(color: C.line, width: 1.2),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (collapsed) ...[
            Text(L.appName,
                style: mono(size: 11, color: C.ink2, w: FontWeight.w700)
                    .copyWith(letterSpacing: 2)),
            const SizedBox(width: 9),
          ],
          Icon(collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              size: 18, color: C.ink3),
          const SizedBox(width: 4),
          Text(collapsed ? 'Show header' : 'Hide header',
              style: mono(size: 9.5, color: C.ink3, w: FontWeight.w600)
                  .copyWith(letterSpacing: 1)),
        ]),
      ),
    );
  }

  /// Full-screen mahjong Focus wall — its own page on mobile (a bottom-nav tab).
  Widget _focusPage() => Container(
        color: C.chronicle ? Colors.transparent : C.paper2,
        padding: EdgeInsets.fromLTRB(C.chronicle ? 52 : 10, 10, C.chronicle ? 52 : 10, 10),
        child: _enamel(
          edge: C.green,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: C.chronicle
                ? const SpreadWall(showHeader: true)
                : const FocusWall(showHeader: true),
          ),
        ),
      );

  /// Bottom nav to switch between the tasks page and the mahjong page (mobile).
  Widget _mobileNav() {
    Widget item(String id, String zh, String en, IconData icon) {
      final on = _mobileView == id;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _mobileView = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: on ? C.green : C.paper,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: on ? C.creamTxt : C.ink3),
              const SizedBox(height: 3),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(zh, style: serifHk(size: 13, color: on ? C.creamTxt : C.ink2)),
                const SizedBox(width: 5),
                Text(en,
                    style: mono(size: 9, color: on ? C.creamTxt : C.ink3)
                        .copyWith(letterSpacing: .5)),
              ]),
            ]),
          ),
        ),
      );
    }

    return Material(
      color: C.paper,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line, width: 1.5))),
          child: Row(children: [
            item('tasks', L.navTasksZh, L.navTasksEn, Icons.check_box_outlined),
            Container(width: 1.5, height: 46, color: C.line),
            item('focus', L.navFocusZh, L.navFocusEn,
                C.chronicle ? Icons.style_outlined : Icons.grid_view_rounded),
          ]),
        ),
      ),
    );
  }

  /// Horizontal group filter for narrow layouts (replaces the side rail).
  Widget _groupChips() => Container(
        height: 40,
        padding: const EdgeInsets.only(left: 12, right: 12, top: 2),
        child: ListView(scrollDirection: Axis.horizontal, children: [
          _groupChip('all', C.chronicle ? 'All' : 'All 全部', C.greenD,
              store.tasks.where((t) => !t.done && !t.daily).length),
          for (final g in store.groups)
            _groupChip(g.key, C.chronicle ? g.name : '${g.name} ${g.zh}', g.c,
                store.tasksIn(g.key).where((t) => !t.done && !t.daily).length),
        ]),
      );

  Widget _groupChip(String key, String label, Color color, int count) {
    final on = store.filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Hoverable(
        onTap: () => store.setFilter(key),
        borderRadius: BorderRadius.circular(8),
        hoverColor: on ? const Color(0x26FFFFFF) : const Color(0x1F000000),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? color : C.paper,
            border: Border.all(color: color, width: 1.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on ? C.creamTxt : C.ink)),
            const SizedBox(width: 6),
            Text('$count',
                style: mono(size: 10, color: on ? C.creamTxt : C.ink3)),
          ]),
        ),
      ),
    );
  }

  Widget _wideLayout() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Fixed-height row so the masthead and TODAY card are always the
              // same height. A bounded height lets CrossAxisAlignment.stretch
              // fill both without IntrinsicHeight (which can't measure the
              // masthead's Wrap or TodayCard's LayoutBuilder and blanks the page).
              if (!store.headerCollapsed) ...[
                SizedBox(
                  height: 176,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _masthead()),
                    const SizedBox(width: 14),
                    const SizedBox(width: 470, child: TodayCard()),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              Align(alignment: Alignment.centerRight, child: _headerCollapseBar()),
              const SizedBox(height: 12),
              Expanded(child: _board()),
            ]),
          ),
        ),
      );

  Widget _board() => _enamel(
        edge: C.green,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 232, child: _groupsRail()),
            Container(width: 2, color: C.green),
            Expanded(child: _tasksColumn()),
            Container(width: 2, color: C.green),
            SizedBox(
                width: 300,
                child: C.chronicle
                    ? const SpreadWall(showHeader: true)
                    : const FocusWall(showHeader: true)),
          ]),
        ),
      );

  List<Group> _groupsToShow() => store.filter == 'all'
      ? store.groups
      : store.groups.where((g) => g.key == store.filter).toList();

  Widget _groupsRail() => Container(
        color: C.paper3,
        padding: const EdgeInsets.fromLTRB(13, 14, 13, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(L.groups,
                style: disp(size: 12, w: FontWeight.w700, color: C.greenD)
                    .copyWith(letterSpacing: .5)),
            const SizedBox(width: 7),
            Text(L.groupsZh,
                style: C.chronicle
                    ? disp(size: 12, w: FontWeight.w600, color: C.greenD)
                        .copyWith(fontStyle: FontStyle.italic)
                    : serifHk(size: 12, color: C.greenD)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(children: [
              _railItem('all', 'All', C.chronicle ? '' : '全部', C.greenD,
                  store.tasks.where((t) => !t.done && !t.daily).length),
              for (final g in store.groups)
                _railItem(g.key, g.name, C.chronicle ? '' : g.zh, g.c,
                    store.tasksIn(g.key).where((t) => !t.done && !t.daily).length,
                    group: g),
              const SizedBox(height: 4),
              _addGroupTile(),
            ]),
          ),
        ]),
      );

  Widget _railItem(String key, String name, String zh, Color color, int count,
          {Group? group}) {
    final active = store.filter == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => store.setFilter(key),
          child: Container(
            decoration: BoxDecoration(
              color: active ? color : C.paper2,
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(7),
              boxShadow: const [
                BoxShadow(color: Color(0x18462D0F), offset: Offset(1.5, 1.5))
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(2.5),
              padding: const EdgeInsets.fromLTRB(8, 7, 2, 7),
              decoration: BoxDecoration(
                border: Border.all(
                    color: (active ? C.creamTxt : color).withValues(alpha: .4), width: 1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: active ? C.creamTxt : C.ink)),
                ),
                if (zh.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(zh, style: serifHk(size: 11.5, color: active ? C.creamTxt : C.ink2)),
                ],
                const SizedBox(width: 8),
                Text('$count', style: mono(size: 11, color: active ? C.creamTxt : C.ink3)),
                if (group != null)
                  SizedBox(
                    width: 22,
                    height: 24,
                    child: PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          size: 15, color: (active ? C.creamTxt : C.ink3).withValues(alpha: .8)),
                      padding: EdgeInsets.zero,
                      splashRadius: 16,
                      onSelected: (v) {
                        if (v == 'rename') _renameGroup(group);
                        if (v == 'del') _confirmDeleteGroup(group);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: _MenuRow(Icons.edit_outlined, 'Rename group')),
                        PopupMenuItem(value: 'del', child: _MenuRow(Icons.delete_outline, 'Delete group', danger: true)),
                      ],
                    ),
                  )
                else
                  const SizedBox(width: 6),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tasksColumn() => Container(
        color: C.paper2,
        child: Column(children: [
          _tasksHeader(),
          _dueSoonBanner(),
          Expanded(
            child: store.viewMode == 'board'
                ? _boardView()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      ..._dailySection(),
                      for (final g in _groupsToShow()) ..._section(g),
                      if (store.showDone) ...[
                        const SizedBox(height: 6),
                        ..._doneSection(),
                      ],
                    ],
                  ),
          ),
          _addBar(),
        ]),
      );

  Widget _tasksHeader() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (ctx, c) {
            final title = Row(mainAxisSize: MainAxisSize.min, children: [
              Text(L.tasks,
                  style: disp(size: 22, w: FontWeight.w700, color: C.ink)
                      .copyWith(letterSpacing: .4)),
              const SizedBox(width: 8),
              Text(L.tasksZh,
                  style: C.chronicle
                      ? disp(size: 17, w: FontWeight.w600, color: C.red)
                          .copyWith(fontStyle: FontStyle.italic)
                      : serifHk(size: 18, color: C.red)),
            ]);
            if (c.maxWidth < 520) {
              // stack: title, then the buttons (wrapping if very narrow)
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: title),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _doneToggleBtn(),
                  _sortBtn(),
                  _viewSwitch(),
                ]),
              ]);
            }
            return Row(children: [
              title,
              const Spacer(),
              _doneToggleBtn(),
              const SizedBox(width: 8),
              _sortBtn(),
              const SizedBox(width: 8),
              _viewSwitch(),
            ]);
          }),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '✓ '),
              TextSpan(text: 'finishes', style: TextStyle(color: C.greenD)),
              const TextSpan(text: '  ·  tap a title to rename  ·  '),
              TextSpan(
                  text: C.chronicle ? 'an olive sprig' : '★',
                  style: TextStyle(
                      color: C.chronicle ? C.olive : C.mustard,
                      fontStyle: C.chronicle ? FontStyle.italic : FontStyle.normal)),
              TextSpan(text: C.chronicle ? ' draws it into ' : ' draws it into the '),
              TextSpan(
                  text: L.focusName,
                  style: C.chronicle
                      ? disp(size: 12, w: FontWeight.w600, color: C.red)
                          .copyWith(fontStyle: FontStyle.italic)
                      : serifHk(size: 12, color: C.green)),
              TextSpan(text: C.chronicle ? '' : ' wall'),
            ]),
            style: TextStyle(fontSize: 12, color: C.ink2, height: 1.3),
          ),
        ]),
      );

  Widget _dueSoonBanner() {
    if (store.viewMode == 'board') return const SizedBox.shrink();
    final soon =
        store.tasks.where((t) => !t.done && !t.daily && store.soon(t)).toList();
    if (soon.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: C.red.withValues(alpha: .06),
        border: Border.all(color: C.red.withValues(alpha: .5), width: 1.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: C.red),
          const SizedBox(width: 7),
          Text(L.dueSoonZh,
              style: C.chronicle
                  ? disp(size: 13, w: FontWeight.w600, color: C.red)
                      .copyWith(fontStyle: FontStyle.italic)
                  : serifHk(size: 13, color: C.red)),
          const SizedBox(width: 5),
          Text(L.dueSoon,
              style: mono(size: 8.5, color: C.red).copyWith(letterSpacing: .8)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final t in soon) _dueSoonChip(t),
        ]),
      ]),
    );
  }

  // A due-soon chip is a read-only heads-up — no tap action (avoids accidental edits).
  Widget _dueSoonChip(Task t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: C.paper2,
          border: Border.all(color: C.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: C.ink)),
          ),
          const SizedBox(width: 6),
          Text(store.dueLabel(t) ?? '',
              style: mono(size: 11, color: C.red).copyWith(fontWeight: FontWeight.w700)),
        ]),
      );

  // ---------------- toolbar / view switch / groups ----------------
  Widget _viewSwitch() {
    Widget seg(String v, String label) {
      final on = store.viewMode == v;
      return Hoverable(
        onTap: () => store.setViewMode(v),
        borderRadius: BorderRadius.zero,
        hoverColor: on ? const Color(0x26FFFFFF) : const Color(0x1F000000),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: on ? C.green : C.paper2,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: on ? C.creamTxt : C.greenD)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
          border: Border.all(color: C.green, width: 2),
          borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('sections', C.chronicle ? 'Sections' : 'Sections 分類'),
        Container(width: 2, height: 30, color: C.green),
        seg('board', C.chronicle ? 'Board' : 'Board 牌桌'),
      ]),
    );
  }

  Widget _doneToggleBtn() {
    final n = store.tasks.where((t) => t.done && !t.daily).length;
    return OutlinedButton(
      onPressed: () => store.setShowDone(!store.showDone),
      style: OutlinedButton.styleFrom(
        foregroundColor: store.showDone ? C.creamTxt : C.ink2,
        backgroundColor: store.showDone ? C.green : C.paper2,
        side: BorderSide(color: store.showDone ? C.green : C.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(C.chronicle ? 'Done ($n)' : '完成 Done ($n)',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _sortBtn() {
    final byDue = store.sortMode == 'due';
    return OutlinedButton.icon(
      onPressed: () => store.setSortMode(byDue ? 'manual' : 'due'),
      icon: Icon(byDue ? Icons.event_available_outlined : Icons.sort, size: 15),
      label: Text(byDue ? 'By date' : 'Sort',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: byDue ? C.creamTxt : C.ink2,
        backgroundColor: byDue ? C.navy : C.paper2,
        side: BorderSide(color: byDue ? C.navy : C.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Widget _boardView() => ScrollConfiguration(
        behavior: const _DragScrollBehavior(),
        child: Listener(
          onPointerSignal: (event) {
            // Only a *horizontal* wheel/trackpad gesture pans the board. A
            // vertical scroll falls through to the column's own task list, so
            // scrolling within a group no longer drags the whole board.
            if (event is PointerScrollEvent && _boardCtl.hasClients) {
              final dx = event.scrollDelta.dx;
              if (dx != 0 && dx.abs() > event.scrollDelta.dy.abs()) {
                final target = (_boardCtl.offset + dx).clamp(
                  _boardCtl.position.minScrollExtent,
                  _boardCtl.position.maxScrollExtent,
                );
                _boardCtl.jumpTo(target);
              }
            }
          },
          child: Scrollbar(
            controller: _boardCtl,
            thumbVisibility: true,
            child: ListView(
              controller: _boardCtl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                for (final g in store.groups) _boardColumn(g),
                _addColumn(),
              ],
            ),
          ),
        ),
      );

  Widget _boardColumn(Group g) {
    final all = store.tasksIn(g.key).where((t) => !t.daily).toList();
    final rows = all.where((t) => !t.done).toList();
    // Honour the global "Done" toggle here too, so completed cards can be
    // reviewed in board mode (shown, de-emphasised, below the active ones).
    final doneRows = store.showDone ? all.where((t) => t.done).toList() : const <Task>[];
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _groupHeader(g, '${rows.length}'),
        Expanded(
          child: ListView(children: [
            for (final t in rows) _taskCard(t),
            if (doneRows.isNotEmpty) ...[
              _boardDoneDivider(doneRows.length),
              for (final t in doneRows)
                Opacity(opacity: .6, child: _taskCard(t)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _boardDoneDivider(int n) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
        child: Row(children: [
          Expanded(child: Divider(color: C.line, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(C.chronicle ? 'DONE · $n' : '完成 DONE · $n',
                style: mono(size: 9, color: C.ink3, w: FontWeight.w700)
                    .copyWith(letterSpacing: 1)),
          ),
          Expanded(child: Divider(color: C.line, thickness: 1)),
        ]),
      );

  Widget _addColumn() => Container(
        width: 190,
        margin: const EdgeInsets.only(right: 14),
        alignment: Alignment.topCenter,
        child: OutlinedButton.icon(
          onPressed: _addGroupDialog,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New group'),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.greenD,
            side: const BorderSide(color: C.green, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      );

  Widget _addGroupTile() => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _addGroupDialog,
          icon: const Icon(Icons.add, size: 16),
          label: Text(C.chronicle ? 'New group' : 'New group 新增', style: const TextStyle(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            foregroundColor: C.greenD,
            side: const BorderSide(color: C.green, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
        ),
      );

  // ---------------- sync ----------------
  Widget _apkButton() => Hoverable(
        onTap: apk.downloadApk,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: C.green.withValues(alpha: .08),
            border: Border.all(color: C.green, width: 1.3),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.android, size: 13, color: C.greenD),
            const SizedBox(width: 5),
            Text('APK',
                style: mono(size: 9.5, color: C.greenD, w: FontWeight.w700)
                    .copyWith(letterSpacing: 1)),
          ]),
        ),
      );

  Widget _syncButton() => ListenableBuilder(
        listenable: SyncService.instance,
        builder: (context, _) {
          final s = SyncService.instance;
          final (IconData icon, String label, Color col) = switch (s.stage) {
            SyncStage.live => (Icons.cloud_done, 'Synced', C.green),
            SyncStage.syncing => (Icons.cloud_sync, 'Syncing…', C.navy),
            SyncStage.error => (Icons.cloud_off, 'Sync error', C.red),
            SyncStage.signedOut => (Icons.cloud_outlined, 'Sync', C.ink3),
          };
          return Hoverable(
            onTap: _openSyncSheet,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: col, width: 1.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: col),
                const SizedBox(width: 5),
                Text(label, style: mono(size: 10, color: col, w: FontWeight.w700)),
              ]),
            ),
          );
        },
      );

  void _openSyncSheet() {
    final emailCtl = TextEditingController(text: SyncService.instance.email ?? '');
    final passCtl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: C.paper2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: ListenableBuilder(
          listenable: SyncService.instance,
          builder: (ctx, _) {
            final s = SyncService.instance;
            final signedIn = s.isSignedIn;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(L.syncZh,
                    style: C.chronicle
                        ? disp(size: 17, w: FontWeight.w600, color: C.red)
                            .copyWith(fontStyle: FontStyle.italic)
                        : serifHk(size: 18, color: C.red)),
                const SizedBox(width: 8),
                Text(L.sync, style: disp(size: 15, w: FontWeight.w700, color: C.ink)),
              ]),
              const SizedBox(height: 4),
              Text(
                signedIn
                    ? 'Signed in — your tasks sync across every device using this email.'
                    : 'Use the same email + password on each device to sync. No emails are sent.',
                style: const TextStyle(fontSize: 12.5, color: C.ink2),
              ),
              const SizedBox(height: 14),
              if (signedIn) ...[
                Row(children: [
                  const Icon(Icons.cloud_done, size: 18, color: C.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.email ?? '', style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink))),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10, left: 26),
                  child: Text(
                      s.lastSyncedAt == null
                          ? 'Waiting for first sync…'
                          : 'Last synced ${_ago(s.lastSyncedAt!)}',
                      style: mono(size: 11, color: C.ink3)),
                ),
                if (s.message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(s.message!, style: const TextStyle(fontSize: 12, color: C.greenD)),
                  ),
                const Text('If a device is out of sync, force it:',
                    style: TextStyle(fontSize: 12, color: C.ink2)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => s.forcePush(),
                      icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                      label: const Text('Use this device', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(backgroundColor: C.green),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => s.forcePull(),
                      icon: const Icon(Icons.cloud_download_outlined, size: 16),
                      label: const Text('Use cloud', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: C.navy, side: const BorderSide(color: C.navy)),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => s.signOut(),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: C.red, side: const BorderSide(color: C.red)),
                ),
              ] else ...[
                TextField(
                  controller: emailCtl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _syncField('Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtl,
                  obscureText: true,
                  decoration: _syncField('Password (6+ characters)'),
                ),
                const SizedBox(height: 10),
                if (s.message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(s.message!,
                        style: TextStyle(
                            fontSize: 12,
                            color: s.stage == SyncStage.error ? C.red : C.greenD)),
                  ),
                FilledButton(
                  onPressed: () => s.connect(emailCtl.text, passCtl.text),
                  style: FilledButton.styleFrom(backgroundColor: C.green),
                  child: const Text('Connect'),
                ),
              ],
              const SizedBox(height: 6),
            ]);
          },
        ),
      ),
    );
  }

  InputDecoration _syncField(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: C.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: C.green, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: C.mustard, width: 1.5)),
      );

  Widget _groupHeader(Group g, String count) => Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
        decoration: BoxDecoration(
          color: g.c,
          borderRadius: BorderRadius.circular(7),
          boxShadow: const [BoxShadow(color: Color(0x24462D0F), offset: Offset(2, 2))],
        ),
        child: Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(g.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: disp(size: 14, w: FontWeight.w700, color: C.creamTxt)
                        .copyWith(letterSpacing: .4)),
              ),
              if (g.zh.isNotEmpty && !C.chronicle) ...[
                const SizedBox(width: 8),
                Text(g.zh,
                    style: serifHk(size: 14, color: C.creamTxt).copyWith(height: 1.1)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Text(count, style: mono(size: 11, color: C.creamTxt)),
          Hoverable(
            onTap: () => _quickAdd(g),
            borderRadius: BorderRadius.circular(6),
            hoverColor: const Color(0x26FFFFFF),
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: C.creamTxt.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.add, size: 18, color: C.creamTxt),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: C.creamTxt),
            onSelected: (v) {
              if (v == 'add') _quickAdd(g);
              if (v == 'rename') _renameGroup(g);
              if (v == 'del') _confirmDeleteGroup(g);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'add',
                  child: _MenuRow(Icons.add, 'Add task')),
              PopupMenuItem(
                  value: 'rename',
                  child: _MenuRow(Icons.edit_outlined, 'Rename group')),
              PopupMenuItem(
                  value: 'del',
                  child: _MenuRow(Icons.delete_outline, 'Delete group', danger: true)),
            ],
          ),
        ]),
      );

  Future<void> _quickAdd(Group g) async {
    final ctl = TextEditingController();
    DateTime? date;
    TimeOfDay? time;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final now = DateTime.now();
          return AlertDialog(
            backgroundColor: C.paper2,
            title: Row(children: [
              Text(L.add, style: serifHk(size: 17, color: C.red)),
              const SizedBox(width: 8),
              Flexible(child: Text(g.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.ink2))),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: ctl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) {
                  if (ctl.text.trim().isNotEmpty) {
                    _commitQuickAdd(g, ctl.text, date, time);
                    Navigator.pop(ctx);
                  }
                },
                decoration: _syncField('Task title'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date ?? now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 3),
                        builder: _themedPicker,
                      );
                      if (d != null) setLocal(() => date = d);
                    },
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(date == null ? 'Date' : _addDateLabel(date!),
                        style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: date == null ? C.ink3 : C.navy,
                        side: BorderSide(color: date == null ? C.line : C.navy)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: date == null
                        ? null
                        : () async {
                            final tt = await showTimePicker(
                                context: ctx,
                                initialTime: time ?? TimeOfDay.now(),
                                initialEntryMode: _timeEntryMode(),
                                builder: _themedPicker);
                            if (tt != null) setLocal(() => time = tt);
                          },
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(time == null ? 'Time' : time!.format(ctx),
                        style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: time == null ? C.ink3 : C.navy,
                        side: BorderSide(color: time == null ? C.line : C.navy)),
                  ),
                ),
              ]),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: C.green),
                onPressed: () {
                  _commitQuickAdd(g, ctl.text, date, time);
                  Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _commitQuickAdd(Group g, String title, DateTime? date, TimeOfDay? time) {
    if (title.trim().isEmpty) return;
    final hhmm = time == null
        ? null
        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    store.addTask(title, g.key, due: date, dueTime: hhmm);
  }

  Future<void> _renameGroup(Group g) async {
    final v = await _promptText('Rename group', g.name);
    if (v != null) store.renameGroup(g, v);
  }

  Future<void> _addGroupDialog() async {
    final v = await _promptText('New group', '');
    if (v != null && v.trim().isNotEmpty) store.addGroup(v);
  }

  Future<void> _confirmDeleteGroup(Group g) async {
    if (store.groups.length <= 1) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.paper2,
        title: const Text('Delete group?'),
        content: Text('Tasks in "${g.name}" move to another group.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) store.deleteGroup(g);
  }

  // ---------------- masthead ----------------
  Widget _masthead() => C.chronicle ? _chronicleMasthead() : _cadenceMasthead();

  // The Greek masthead: a painting chosen by the time of day, the CHRONICLE
  // wordmark, and the same made-for / APK / Sync controls over a dark veil.
  Widget _chronicleMasthead() {
    final now = DateTime.now();
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: 180,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset(Chron.mastAssets[Chron.slotNow()],
              fit: BoxFit.cover, alignment: const Alignment(0, -0.1)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33102A49), Color(0x00102A49), Color(0x22102A49), Color(0xE00D2340)],
                stops: [0, .34, .6, 1],
              ),
            ),
          ),
          Positioned(
            top: 11, left: 12, right: 12,
            child: Row(children: [
              Flexible(child: _chronChip(L.madeFor)),
              const Spacer(),
              if (apk.canDownloadApk) _apkButton(),
              const SizedBox(width: 8),
              _syncButton(),
            ]),
          ),
          Positioned(
            left: 16, right: 16, bottom: 11,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(L.appName,
                    style: disp(size: 40, w: FontWeight.w700, color: const Color(0xFFF6F0DF)).copyWith(
                        letterSpacing: 4,
                        shadows: const [Shadow(color: Color(0xAA0B1E38), offset: Offset(0, 2), blurRadius: 10)])),
              ),
              Text(_chronDate(now),
                  style: mono(size: 11.5, color: const Color(0xCCEEF2F6)).copyWith(fontStyle: FontStyle.italic)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chronChip(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xAA0E2340),
          border: Border.all(color: const Color(0x88E9E0C6)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(s,
            style: mono(size: 9, color: const Color(0xFFF4EEDA), w: FontWeight.w600).copyWith(letterSpacing: 1.2)),
      );

  static const _wdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _mons = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  String _chronDate(DateTime d) => '${_wdays[d.weekday - 1]}, ${d.day} ${_mons[d.month - 1]}';

  Widget _cadenceMasthead() => _enamel(
        edge: C.red,
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const LatticeStrip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: C.red, width: 1.5),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(L.madeFor,
                          style: mono(size: 9.5, color: C.red, w: FontWeight.w700)
                              .copyWith(letterSpacing: 1.6)),
                    ),
                    // A Wrap (not Row) so APK + Sync flow to a new line on
                    // narrow screens instead of overflowing next to the chip.
                    Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (apk.canDownloadApk) _apkButton(),
                      _syncButton(),
                    ]),
                  ],
                ),
                const SizedBox(height: 16),
                // scale-down so the title never overflows on narrow/fold screens
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (L.appZh.isNotEmpty) ...[
                          Text(L.appZh,
                              style: serifHk(size: 66, color: C.red).copyWith(height: 1)),
                          const SizedBox(width: 16),
                        ] else ...[
                          const SealMark(size: 58),
                          const SizedBox(width: 16),
                        ],
                        Text(L.appName,
                            style: disp(size: 44, w: FontWeight.w700, color: C.chronicle ? C.red : C.greenD)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      );

  // ---------------- sections ----------------
  List<Widget> _section(Group g) {
    final rows = store
        .sortRows(store.tasksIn(g.key).where((t) => !t.done && !t.daily).toList());
    final total = store.tasksIn(g.key).where((t) => !t.daily).length;
    // In the "All" view, don't show a header for a group whose only tasks are
    // already completed (unless the Done archive is being shown) — an empty
    // "0/1" section reads as if tasks still exist.
    if (rows.isEmpty && !store.showDone && store.filter == 'all') return [];
    return [
      _groupHeader(g, '${rows.length}/$total'),
      for (final t in rows) _taskCard(t),
      const SizedBox(height: 20),
    ];
  }

  Widget _sectionHeader(String name, String zh, Color color, String count,
          {Widget? trailing}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
          boxShadow: const [BoxShadow(color: Color(0x24462D0F), offset: Offset(2, 2))],
        ),
        child: Row(children: [
          Text(name.toUpperCase(),
              style: disp(size: 14, w: FontWeight.w700, color: C.creamTxt)
                  .copyWith(letterSpacing: .4)),
          if (zh.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(zh, style: serifHk(size: 14, color: C.creamTxt).copyWith(height: 1.1)),
          ],
          const Spacer(),
          Text(count, style: mono(size: 11, color: C.creamTxt)),
          if (trailing != null) ...[const SizedBox(width: 10), trailing],
        ]),
      );

  List<Widget> _doneSection() {
    final rows = store.tasks.where((t) => t.done && !t.daily).toList();
    return [
      _sectionHeader(L.done, L.doneZh, C.ink3, '${rows.length}',
          trailing: rows.isEmpty
              ? null
              : Material(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    onTap: _clearDoneWithUndo,
                    borderRadius: BorderRadius.circular(5),
                    hoverColor: const Color(0x55FFFFFF),
                    splashColor: const Color(0x44FFFFFF),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.delete_sweep_outlined, size: 14, color: C.creamTxt),
                        const SizedBox(width: 4),
                        Text('Clear', style: mono(size: 10, color: C.creamTxt)),
                      ]),
                    ),
                  ),
                )),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('clears automatically a week after completion',
            style: mono(size: 10, color: C.ink3)),
      ),
      for (final t in rows) _taskCard(t),
      const SizedBox(height: 20),
    ];
  }

  void _clearDoneWithUndo() {
    final removed = store.tasks.where((t) => t.done && !t.daily).toList();
    if (removed.isEmpty) return;
    store.clearDone();
    _snack('Cleared ${removed.length} finished', () {
      for (final t in removed) {
        store.insertTask(t, store.tasks.length);
      }
    });
  }

  // ---------------- daily rituals ----------------
  List<Widget> _dailySection() {
    final rows = store.dailies();
    // Only meaningful in the "All" view; hide when filtered to a single group.
    if (store.filter != 'all') return [];
    final done = rows.where(store.dailyDoneToday).length;
    return [
      _dailyHeader(rows.isEmpty ? '' : '$done/${rows.length}'),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Text('tap ＋ to add a daily ritual (resets every day)',
              style: mono(size: 10.5, color: C.ink3)),
        )
      else
        for (final t in rows) _dailyRow(t),
      const SizedBox(height: 18),
    ];
  }

  Widget _dailyHeader(String count) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: C.greenD,
          borderRadius: BorderRadius.circular(7),
          boxShadow: const [BoxShadow(color: Color(0x24462D0F), offset: Offset(2, 2))],
        ),
        child: Row(children: [
          Text(L.dailyZh,
              style: serifHk(size: 14, color: C.creamTxt).copyWith(
                  height: 1.1, fontStyle: C.chronicle ? FontStyle.italic : FontStyle.normal)),
          const SizedBox(width: 8),
          Text(L.daily,
              style: disp(size: 12, w: FontWeight.w700, color: C.creamTxt)
                  .copyWith(letterSpacing: .5)),
          const Spacer(),
          Text(count, style: mono(size: 11, color: C.creamTxt)),
          const SizedBox(width: 9),
          Hoverable(
            onTap: _addDaily,
            borderRadius: BorderRadius.circular(6),
            hoverColor: const Color(0x26FFFFFF),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                  color: const Color(0x30FFFFFF), borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.add, size: 16, color: C.creamTxt),
            ),
          ),
        ]),
      );

  Widget _dailyRow(Task t) {
    final done = store.dailyDoneToday(t);
    final streak = store.dailyStreak(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9, left: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Hoverable(
          onTap: () => store.toggleDailyDone(t),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: done ? C.greenD : C.paper,
              border: Border.all(color: C.greenD, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: done ? const Icon(Icons.check, size: 13, color: C.creamTxt) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _editingTaskId == t.id
              ? TextField(
                  controller: _editCtl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _commitEditTitle(t),
                  onTapOutside: (_) => _commitEditTitle(t),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: C.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: C.paper,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: C.mustard, width: 1.5)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: const BorderSide(color: C.mustard, width: 1.5)),
                  ),
                )
              : GestureDetector(
                  onTap: () => _startEditTitle(t),
                  child: Text(t.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: done ? C.ink3 : C.ink,
                        decoration: done ? TextDecoration.lineThrough : null,
                      )),
                ),
        ),
        if (streak > 0) ...[
          const Icon(Icons.local_fire_department, size: 15, color: C.mustard),
          const SizedBox(width: 1),
          Text('$streak', style: mono(size: 12, color: C.mustard)),
          const SizedBox(width: 4),
        ],
        _dailyMenu(t),
      ]),
    );
  }

  Widget _dailyMenu(Task t) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18, color: C.ink3),
        padding: EdgeInsets.zero,
        onSelected: (v) {
          switch (v) {
            case 'rename':
              _startEditTitle(t);
              break;
            case 'stop':
              store.setDaily(t, false);
              break;
            case 'del':
              store.deleteTask(t);
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: _MenuRow(Icons.edit_outlined, 'Rename')),
          const PopupMenuItem(
              value: 'stop', child: _MenuRow(Icons.playlist_remove, 'Stop being daily')),
          const PopupMenuItem(value: 'del', child: _MenuRow(Icons.delete_outline, 'Delete', danger: true)),
        ],
      );

  void _addDaily() {
    store.addDaily('New daily');
    final rows = store.dailies();
    if (rows.isNotEmpty) _startEditTitle(rows.first);
  }

  // ---------------- task card ----------------
  Widget _taskCard(Task t) {
    final g = store.groupOf(t.group);
    final due = store.dueLabel(t);
    final soon = store.soon(t);
    final overdue = store.isOverdue(t);
    final lit = _highlightId == t.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          boxShadow: lit
              ? [BoxShadow(color: C.mustard.withValues(alpha: .9), blurRadius: 0, spreadRadius: 3)]
              : const [],
        ),
        child: _enamel(
          edge: overdue ? C.red : g.c,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _checkbox(t, g.c),
              const SizedBox(width: 12),
              Expanded(
                child: _editingTaskId == t.id
                    ? TextField(
                        controller: _editCtl,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _commitEditTitle(t),
                        onTapOutside: (_) => _commitEditTitle(t),
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700, color: C.ink),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: C.paper,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: const BorderSide(color: C.mustard, width: 1.5)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: const BorderSide(color: C.mustard, width: 1.5)),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => _startEditTitle(t),
                        child: Text(t.title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: t.done ? C.ink3 : C.ink,
                              decoration:
                                  t.done ? TextDecoration.lineThrough : null,
                            )),
                      ),
              ),
              if (!t.done)
                Hoverable(
                  onTap: () => store.toggleStar(t),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: C.chronicle
                        ? OliveSprig(lit: t.star)
                        : Icon(t.star ? Icons.star : Icons.star_border,
                            size: 21, color: t.star ? C.mustard : C.line),
                  ),
                )
              else if (C.chronicle)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: WaxSeal(),
                ),
              _menu(t),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 8),
              child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _chip(g.name.toUpperCase(), g.c),
                Hoverable(
                  onTap: () => _editDue(t),
                  borderRadius: BorderRadius.circular(5),
                  child: due == null
                      ? _iconChip(Icons.event_outlined)
                      : overdue
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                  color: C.red, borderRadius: BorderRadius.circular(5)),
                              child: Text('◷ $due',
                                  style: mono(size: 10.5, color: C.creamTxt)
                                      .copyWith(fontWeight: FontWeight.w700)),
                            )
                          : Text('◷ $due',
                              style: mono(size: 11, color: soon ? C.red : C.ink3)),
                ),
                if (t.pri) _priBadge(),
                if (t.sub.isNotEmpty)
                  GestureDetector(
                    onTap: () => store.toggleOpen(t),
                    child: _softChip('${t.open ? '▾' : '▸'} ${t.sub.where((s) => s.done).length}/${t.sub.length}'),
                  ),
              ]),
            ),
            if (t.open) _subs(t, g.c),
          ],
        ),
        ),
      ),
    );
  }

  Widget _checkbox(Task t, Color color) => Hoverable(
        onTap: () => _completeWithUndo(t),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: t.done ? color : C.paper,
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: t.done ? const Icon(Icons.check, size: 13, color: C.creamTxt) : null,
        ),
      );

  Widget _menu(Task t) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18, color: C.ink3),
        padding: EdgeInsets.zero,
        onSelected: (v) {
          switch (v) {
            case 'date':
              _pickDue(t);
              break;
            case 'time':
              _pickTime(t);
              break;
            case 'pri':
              store.togglePri(t);
              break;
            case 'sub':
              store.toggleOpen(t);
              break;
            case 'tomorrow':
              _pushToTomorrow(t);
              break;
            case 'move':
              _moveTask(t);
              break;
            case 'daily':
              store.setDaily(t, true);
              break;
            case 'del':
              _deleteWithUndo(t);
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'date', child: _MenuRow(Icons.event_outlined, 'Set due date')),
          PopupMenuItem(
              value: 'time',
              child: _MenuRow(Icons.schedule,
                  t.dueTime == null ? 'Set time' : 'Change time')),
          const PopupMenuItem(
              value: 'tomorrow', child: _MenuRow(Icons.wb_sunny_outlined, 'Due tomorrow')),
          PopupMenuItem(
              value: 'pri',
              child: _MenuRow(Icons.priority_high,
                  t.pri ? 'Clear priority (${L.pri})' : 'Mark priority (${L.pri})')),
          const PopupMenuItem(value: 'sub', child: _MenuRow(Icons.checklist, 'Add / show subtasks')),
          const PopupMenuItem(value: 'move', child: _MenuRow(Icons.drive_file_move_outline, 'Move to group…')),
          const PopupMenuItem(value: 'daily', child: _MenuRow(Icons.repeat, 'Make it a daily')),
          const PopupMenuItem(value: 'del', child: _MenuRow(Icons.delete_outline, 'Delete', danger: true)),
        ],
      );

  Widget _subs(Task t, Color color) => Container(
        margin: const EdgeInsets.only(top: 10, left: 2),
        padding: const EdgeInsets.only(top: 9),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: C.line, style: BorderStyle.solid))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final s in t.sub)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                GestureDetector(
                  onTap: () => store.toggleSub(s),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: s.done ? color : C.paper,
                      border: Border.all(color: color, width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: s.done ? const Icon(Icons.check, size: 10, color: C.creamTxt) : null,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(s.title,
                      style: TextStyle(
                        fontSize: 13,
                        color: s.done ? C.ink3 : C.ink,
                        decoration: s.done ? TextDecoration.lineThrough : null,
                      )),
                ),
                GestureDetector(
                  onTap: () => store.deleteSub(t, s),
                  child: const Icon(Icons.close, size: 14, color: C.ink3),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () => _addSub(t),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4), foregroundColor: C.greenD),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('subtask', style: TextStyle(fontSize: 12.5)),
          ),
        ]),
      );

  // ---------------- chips ----------------
  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: mono(size: 10, color: color, w: FontWeight.w700)),
      );

  Widget _iconChip(IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: C.line, width: 1),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 13, color: C.ink3),
      );

  Widget _softChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: C.line, width: 1),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(label, style: mono(size: 11, color: C.ink3)),
      );

  Widget _priBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(5)),
        child: Text(L.pri,
            style: C.chronicle
                ? disp(size: 10, w: FontWeight.w700, color: C.creamTxt)
                    .copyWith(letterSpacing: .5)
                : serifHk(size: 11, color: C.creamTxt)),
      );

  // ---------------- add bar ----------------
  Widget _addBar() {
    final field = TextField(
      controller: _addCtl,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submitAdd(),
      decoration: InputDecoration(
        isDense: true,
        hintText: '＋ new task…',
        filled: true,
        fillColor: C.paper2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: C.green, width: 1.5)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: C.mustard, width: 1.5)),
      ),
    );
    final groupSel = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: C.paper2,
          border: Border.all(color: C.green, width: 1.5),
          borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _addGroup,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: C.ink),
          items: [
            for (final g in store.groups)
              DropdownMenuItem(value: g.key, child: Text(g.name, style: const TextStyle(fontSize: 12))),
          ],
          onChanged: (v) => setState(() => _addGroup = v ?? _addGroup),
        ),
      ),
    );
    final addBtn = FilledButton(
      onPressed: _submitAdd,
      style: FilledButton.styleFrom(
          backgroundColor: C.mustard,
          foregroundColor: C.greenD,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: Text(L.add, style: serifHk(size: 13, color: C.greenD)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: const BoxDecoration(
        color: C.paper,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        if (c.maxWidth < 470) {
          // narrow: task field on its own line, controls below
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            field,
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: groupSel),
              const SizedBox(width: 8),
              _addDateBtn(),
              const SizedBox(width: 8),
              addBtn,
            ]),
          ]);
        }
        return Row(children: [
          Expanded(child: field),
          const SizedBox(width: 8),
          groupSel,
          const SizedBox(width: 8),
          _addDateBtn(),
          const SizedBox(width: 8),
          addBtn,
        ]);
      }),
    );
  }

  Widget _addDateBtn() {
    final has = _addDate != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _pickAddDate,
        child: Container(
          height: 44,
          padding: EdgeInsets.fromLTRB(10, 0, has ? 4 : 10, 0),
          decoration: BoxDecoration(
              color: has ? C.navy.withValues(alpha: .08) : C.paper2,
              border: Border.all(color: has ? C.navy : C.green, width: 1.5),
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event, size: 16, color: has ? C.navy : C.ink3),
            if (has) ...[
              const SizedBox(width: 5),
              Text(_addDateLabel(_addDate!),
                  style: mono(size: 11, color: C.navy).copyWith(fontWeight: FontWeight.w700)),
              GestureDetector(
                onTap: () => setState(() => _addDate = null),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 13, color: C.navy),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  String _addDateLabel(DateTime d) {
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final days = DateTime(d.year, d.month, d.day).difference(t0).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'tmr';
    if (days > 0 && days < 7) {
      return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.weekday % 7];
    }
    return '${d.month}/${d.day}';
  }

  Future<void> _pickAddDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _addDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      builder: _themedPicker,
    );
    if (picked != null) setState(() => _addDate = picked);
  }

  /// Wraps a date/time picker in the cha-chaan-teng palette.
  Widget _themedPicker(BuildContext ctx, Widget? child) => Theme(
        data: Theme.of(ctx).copyWith(
          textTheme: GoogleFonts.hankenGroteskTextTheme(Theme.of(ctx).textTheme),
          colorScheme: const ColorScheme.light(
            primary: C.red,
            onPrimary: C.creamTxt,
            surface: C.paper2,
            onSurface: C.ink,
            secondary: C.green,
            onSecondary: C.creamTxt,
            surfaceTint: Colors.transparent,
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: C.paper2,
            headerBackgroundColor: C.red,
            headerForegroundColor: C.creamTxt,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            todayForegroundColor: WidgetStateProperty.all(C.red),
            todayBorder: const BorderSide(color: C.red),
          ),
          timePickerTheme: TimePickerThemeData(
            backgroundColor: C.paper2,
            dialBackgroundColor: C.paper,
            hourMinuteColor: C.paper,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: C.red),
          ),
        ),
        child: child!,
      );

  /// On phones/folds the clock dial gets squished, so use keypad entry there.
  TimePickerEntryMode _timeEntryMode() =>
      MediaQuery.of(context).size.width < 1040
          ? TimePickerEntryMode.inputOnly
          : TimePickerEntryMode.input;

  /// "14:30" -> TimeOfDay, or null.
  TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// Tap the due chip: pick the date, then the time in one flow (Cancel on the
  /// time step just leaves the time unchanged).
  Future<void> _editDue(Task t) async {
    await _pickDue(t);
    if (t.dueISO == null) return;
    await _pickTime(t);
  }

  /// Set/clear a task's due time (a due date is set first if needed).
  Future<void> _pickTime(Task t) async {
    if (t.dueISO == null) {
      await _pickDue(t);
      if (t.dueISO == null) return; // cancelled — no date to anchor the time
    }
    final tod = await showTimePicker(
      context: context,
      initialTime: _parseTime(t.dueTime) ?? const TimeOfDay(hour: 9, minute: 0),
      initialEntryMode: _timeEntryMode(),
      builder: _themedPicker,
    );
    if (tod != null) {
      store.setDueTime(t,
          '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}');
    }
  }

  void _submitAdd() {
    final text = _addCtl.text.trim();
    if (text.isEmpty) return;
    store.addTask(text, _addGroup, due: _addDate);
    _addCtl.clear();
    setState(() => _addDate = null);
  }

  // ---------------- dialogs ----------------
  Future<void> _addSub(Task t) async {
    final v = await _promptText('New subtask', '');
    if (v != null && v.trim().isNotEmpty) store.addSub(t, v);
  }

  Future<void> _pickDue(Task t) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: CadenceStore.parseISO(t.dueISO) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      builder: _themedPicker,
    );
    if (d != null) store.setDue(t, d);
  }

  Future<void> _moveTask(Task t) async {
    final key = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.paper2,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final g in store.groups)
            ListTile(
              leading: Container(width: 14, height: 14, decoration: BoxDecoration(color: g.c, borderRadius: BorderRadius.circular(3))),
              title: Text(g.name),
              onTap: () => Navigator.pop(context, g.key),
            ),
        ]),
      ),
    );
    if (key != null) store.moveTask(t, key);
  }

  Future<String?> _promptText(String title, String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.paper2,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.green),
              onPressed: () => Navigator.pop(context, ctl.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  // ---------------- enamel container ----------------
  Widget _enamel({required Color edge, required Widget child, EdgeInsets padding = EdgeInsets.zero}) =>
      Container(
        decoration: BoxDecoration(
          color: C.paper2,
          border: Border.all(color: edge, width: 2),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Color(0x22462D0F), offset: Offset(2, 2))],
        ),
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: padding,
          decoration: BoxDecoration(
            border: Border.all(color: edge.withValues(alpha: .5), width: 1.2),
            borderRadius: BorderRadius.circular(5),
          ),
          child: child,
        ),
      );
}

/// Lets the board pan by mouse drag (not just touch/trackpad), so wide-screen
/// mouse users can scroll the board horizontally.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// The green 窗花 (window-grille) lattice strip across the top of the masthead.
class LatticeStrip extends StatelessWidget {
  const LatticeStrip({super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: SizedBox(
          height: 15,
          width: double.infinity,
          child: CustomPaint(painter: _LatticePainter()),
        ),
      );
}

class _LatticePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = C.paper2);
    final p = Paint()
      ..color = C.green.withValues(alpha: .85)
      ..strokeWidth = 1.6;
    for (double x = 0; x <= size.width; x += 15) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += 15) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Chronicle's logogram: a red wax seal with a cream "C" monogram, standing in
/// for Cadence's 節奏 in the masthead.
class SealMark extends StatelessWidget {
  final double size;
  const SealMark({super.key, this.size = 58});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _SealPainter()));
}

class _SealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(w * .16)),
      Paint()..color = C.red,
    );
    // cream inner keyline
    final inset = w * .12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, w - 2 * inset, s.height - 2 * inset),
          Radius.circular(w * .08)),
      Paint()
        ..color = C.creamTxt.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .03,
    );
    // a cream "C" monogram
    final mark = Paint()
      ..color = C.creamTxt
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .08
      ..strokeCap = StrokeCap.round;
    final rad = w * .21;
    const pi = 3.14159;
    // a "C": arc with a gap on the right side
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2, s.height / 2), radius: rad),
      0.30 * pi, // start lower-right
      1.40 * pi, // sweep clockwise, leaving the right open
      false,
      mark,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
