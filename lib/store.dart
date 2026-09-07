import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Reactive, persisted app state. Every mutation notifies listeners and saves.
class CadenceStore extends ChangeNotifier {
  static const _key = 'cadence_v1';

  List<Group> groups = defaultGroups();
  List<Task> tasks = [];
  List<int> wall = []; // task ids on the mahjong wall, in order
  List<Tile> deck = _buildDeck();
  int _uid = 0;
  int streak = 0;
  int _dragCycle = 0;
  String viewMode = 'sections';
  String filter = 'all'; // 'all' or a group key (left-rail selection)
  bool showDone = false;
  int updatedAt = 0; // ms since epoch of the last local change (for sync LWW)

  int _newId() => ++_uid;

  static List<Tile> _buildDeck() {
    final d = <Tile>[];
    for (final s in ['m', 'p', 's']) {
      for (var v = 1; v <= 9; v++) {
        for (var k = 0; k < 4; k++) d.add(Tile(s, v));
      }
    }
    for (var v = 1; v <= 3; v++) {
      for (var k = 0; k < 4; k++) d.add(Tile('z', v));
    }
    d.shuffle(Random());
    return d;
  }

  static const deckTotal = 120;

  // ---------- persistence ----------
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) {
      _seed();
      return;
    }
    try {
      applyState(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _seed();
    }
  }

  /// The full app state as a JSON-serialisable map (used for local persistence
  /// and for cross-device sync).
  Map<String, dynamic> exportState() => {
        'groups': groups.map((g) => g.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'wall': wall,
        'deck': deck.map((t) => t.toJson()).toList(),
        'uid': _uid,
        'streak': streak,
        'viewMode': viewMode,
        'filter': filter,
        'showDone': showDone,
        'updatedAt': updatedAt,
      };

  /// Replace the whole in-memory state from a map (from disk or from the cloud).
  void applyState(Map<String, dynamic> j) {
    groups = ((j['groups'] ?? []) as List)
        .map((e) => Group.fromJson(e as Map<String, dynamic>))
        .toList();
    tasks = ((j['tasks'] ?? []) as List)
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
    wall = ((j['wall'] ?? []) as List).map((e) => e as int).toList();
    _uid = j['uid'] ?? 0;
    streak = j['streak'] ?? 0;
    viewMode = j['viewMode'] ?? 'sections';
    filter = j['filter'] ?? 'all';
    showDone = j['showDone'] ?? false;
    updatedAt = j['updatedAt'] ?? 0;
    final rawDeck = j['deck'];
    if (rawDeck is List) {
      deck = rawDeck.map((e) => Tile.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (groups.isEmpty) groups = defaultGroups();
    _reconcile();
  }

  /// Apply cloud state, persist it locally (so disk mirrors the cloud and a
  /// later resume can't push stale data back), and notify the UI.
  void applyRemoteState(Map<String, dynamic> j) {
    applyState(j); // sets updatedAt from the cloud payload
    save();
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(exportState()));
  }

  /// Notify listeners without persisting (used after an external reload).
  void notify() => notifyListeners();

  /// Stamp the current local state as the newest (for a manual "use this
  /// device" push that must win the sync conflict).
  void touch() {
    updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    save();
  }

  void _changed() {
    updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    save();
  }

  /// Ensure every starred task has a tile and is on the wall; keep the deck sane.
  void _reconcile() {
    // keep each group's Chinese label in sync with its (possibly renamed) name
    for (final g in groups) {
      final z = zhForName(g.name);
      if (z.isNotEmpty) g.zh = z;
    }
    // a finished task must never be on the mahjong wall or hold a tile, but it
    // keeps its star as focus membership (so it shows, struck through, on the
    // widget's Focus page).
    for (final t in tasks.where((t) => t.done)) {
      wall.remove(t.id);
      if (t.tile != null) {
        _returnTile(t.tile);
        t.tile = null;
      }
    }
    // remove wall ids that no longer point at an active starred task
    wall.removeWhere((id) {
      final t = tasks.where((x) => x.id == id);
      return t.isEmpty || !t.first.star || t.first.done;
    });
    for (final t in tasks.where((t) => t.star && !t.done)) {
      t.tile ??= t.pri ? drawDragon() : drawTile();
      if (!wall.contains(t.id)) wall.add(t.id);
    }
    // top up dragons for old saves
    for (var v = 1; v <= 3; v++) {
      final inPlay = tasks.where((t) => t.tile?.suit == 'z' && t.tile?.val == v).length;
      final inDeck = deck.where((t) => t.suit == 'z' && t.val == v).length;
      for (var m = 4 - inPlay - inDeck; m > 0; m--) deck.add(Tile('z', v));
    }
  }

  void _seed() {
    updatedAt = 0; // baseline sample data — real cloud/local data always wins
    groups = defaultGroups();
    String iso(int days) {
      final d = DateTime.now().add(Duration(days: days));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    tasks = [
      Task(id: _newId(), title: 'Ship the widget layout', group: 'side', star: true),
      Task(id: _newId(), title: 'Finish stats problem set', group: 'uni', dueISO: iso(2), star: true),
      Task(id: _newId(), title: 'Renew bus pass', group: 'errand', star: true),
      Task(id: _newId(), title: 'Call the dentist', group: 'health', star: true, pri: true),
      Task(id: _newId(), title: 'Draft the sync schema (Drift + tables)', group: 'side'),
      Task(id: _newId(), title: 'Read chapter 4 before lecture', group: 'uni', dueISO: iso(1)),
      Task(id: _newId(), title: 'Water the plants', group: 'home', done: true),
      Task(id: _newId(), title: 'Reply to Sam about the weekend', group: 'home'),
      Task(id: _newId(), title: 'Push the offline cache branch', group: 'side'),
      Task(id: _newId(), title: 'Submit lab report', group: 'uni', dueISO: iso(4)),
    ];
    // seed the starter wall so it forms a reachable 上 (三四五萬 with a 索 to move)
    final seed = {
      'Ship the widget layout': Tile('m', 3),
      'Finish stats problem set': Tile('m', 4),
      'Renew bus pass': Tile('s', 7),
      'Call the dentist': Tile('z', 1), // priority → 中
    };
    for (final t in tasks.where((t) => t.star)) {
      final s = seed[t.title];
      t.tile = s == null ? drawTile() : _takeSpecific(s.suit, s.val);
      wall.add(t.id);
    }
    save();
  }

  // ---------- deck ----------
  Tile? _takeSpecific(String suit, int val) {
    final i = deck.indexWhere((t) => t.suit == suit && t.val == val);
    if (i >= 0) return deck.removeAt(i);
    return Tile(suit, val);
  }

  Tile? drawTile() {
    for (var i = deck.length - 1; i >= 0; i--) {
      if (deck[i].suit != 'z') return deck.removeAt(i);
    }
    return null;
  }

  Tile? drawDragon() {
    for (var k = 0; k < 3; k++) {
      final v = (_dragCycle++ % 3) + 1;
      final i = deck.indexWhere((t) => t.suit == 'z' && t.val == v);
      if (i >= 0) return deck.removeAt(i);
    }
    final j = deck.indexWhere((t) => t.suit == 'z');
    return j >= 0 ? deck.removeAt(j) : drawTile();
  }

  void _returnTile(Tile? t) {
    if (t != null) deck.add(t);
  }

  int get deckLeft => deck.length;

  // ---------- lookups ----------
  Group groupOf(String key) =>
      groups.firstWhere((g) => g.key == key, orElse: () => groups.first);

  List<Task> tasksIn(String key) => tasks.where((t) => t.group == key).toList();

  Task? byId(int id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Tasks currently on the wall, in wall order.
  List<Task> wallTasks() => wall
      .map((id) => byId(id))
      .whereType<Task>()
      .where((t) => t.tile != null && !t.done)
      .toList();

  // ---------- task mutations ----------
  void addTask(String title, String group, {DateTime? due}) {
    final t = Task(
        id: _newId(),
        title: title.trim().isEmpty ? 'New task' : title.trim(),
        group: group);
    if (due != null) _applyDue(t, due);
    tasks.insert(0, t);
    _changed();
  }

  void deleteTask(Task t) {
    if (t.star) {
      wall.remove(t.id);
      _returnTile(t.tile);
      t.tile = null;
    }
    tasks.remove(t);
    _changed();
  }

  void toggleDone(Task t) {
    t.done = !t.done;
    if (t.done) {
      // finishing discards the tile and leaves the mahjong wall, but the task
      // stays a "focus" item (star) so it still shows on the widget's Focus
      // page, struck through, instead of vanishing.
      final before = wall.length;
      final wasOnWall = wall.remove(t.id);
      if (t.tile != null) {
        _returnTile(t.tile);
        t.tile = null;
      }
      if (wasOnWall && before > 0 && wall.isEmpty) streak++;
    } else if (t.star || t.pri) {
      // un-finishing a focus / urgent task draws it a fresh tile back onto the wall
      final tile = t.pri ? drawDragon() : drawTile();
      if (tile != null) {
        t.tile = tile;
        t.star = true;
        if (!wall.contains(t.id)) wall.add(t.id);
      }
    }
    _changed();
  }

  /// Returns true if a tile was newly drawn onto the wall (for 自摸 detection).
  bool toggleStar(Task t) {
    if (t.done) return false; // a finished task can't be on the wall
    if (t.star) {
      wall.remove(t.id);
      _returnTile(t.tile);
      t.tile = null;
      t.star = false;
      _changed();
      return false;
    } else {
      final tile = t.pri ? drawDragon() : drawTile();
      if (tile == null) return false; // deck empty
      t.tile = tile;
      t.star = true;
      wall.add(t.id);
      _changed();
      return true;
    }
  }

  bool togglePri(Task t) {
    t.pri = !t.pri;
    if (t.done) {
      _changed(); // priority flag only; no wall changes for finished tasks
      return false;
    }
    var drew = false;
    if (t.pri && !t.star) {
      final tile = drawDragon();
      if (tile != null) {
        t.tile = tile;
        t.star = true;
        wall.add(t.id);
        drew = true;
      }
    } else if (t.star) {
      _returnTile(t.tile);
      t.tile = (t.pri ? drawDragon() : drawTile()) ?? Tile(t.pri ? 'z' : 'm', 1);
    }
    _changed();
    return drew;
  }

  void reorderWall(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final id = wall.removeAt(oldIndex);
    wall.insert(newIndex, id);
    _changed();
  }

  void bumpStreak() {
    streak++;
    _changed();
  }

  void setTitle(Task t, String v) {
    if (v.trim().isNotEmpty) t.title = v.trim();
    _changed();
  }

  void _applyDue(Task t, DateTime? d) {
    t.dueISO = d == null
        ? null
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void setDue(Task t, DateTime? d) {
    _applyDue(t, d);
    _changed();
  }

  void moveTask(Task t, String group) {
    t.group = group;
    _changed();
  }

  // ---------- subtasks ----------
  void toggleOpen(Task t) {
    t.open = !t.open;
    _changed();
  }

  void addSub(Task t, String title) {
    if (title.trim().isEmpty) return;
    t.sub.add(SubTask(title.trim()));
    t.open = true;
    _changed();
  }

  void toggleSub(SubTask s) {
    s.done = !s.done;
    _changed();
  }

  void deleteSub(Task t, SubTask s) {
    t.sub.remove(s);
    _changed();
  }

  // ---------- groups ----------
  static const _newPalette = [0xFF7B3F3F, 0xFF556B2F, 0xFF35637A, 0xFF8A5A2B, 0xFF5E4B8E];

  void addGroup(String name) {
    if (name.trim().isEmpty) return;
    final key = 'g${DateTime.now().millisecondsSinceEpoch}';
    groups.add(Group(
        key: key,
        name: name.trim(),
        zh: zhForName(name),
        color: _newPalette[groups.length % _newPalette.length]));
    _changed();
  }

  void renameGroup(Group g, String name) {
    if (name.trim().isNotEmpty) {
      g.name = name.trim();
      g.zh = zhForName(name);
    }
    _changed();
  }

  // Offline English→Chinese dictionary for group names. (The real app can swap
  // this for on-device ML Kit translation; this keeps it working offline.)
  static const Map<String, String> _zhDict = {
    // study / school
    'uni': '學業', 'university': '學業', 'college': '學業', 'school': '學業',
    'study': '學業', 'studies': '學業', 'academic': '學業', 'academics': '學業',
    'class': '課程', 'classes': '課程', 'course': '課程', 'courses': '課程',
    'lecture': '課堂', 'homework': '功課', 'assignment': '功課', 'exam': '考試',
    'computer': '電腦', 'computing': '電腦', 'cs': '電腦', 'code': '編程',
    'coding': '編程', 'programming': '編程', 'science': '科學', 'math': '數學',
    'maths': '數學', 'physics': '物理', 'chemistry': '化學', 'biology': '生物',
    'humanities': '人文', 'history': '歷史', 'language': '語文',
    'languages': '語文', 'english': '英文', 'writing': '寫作', 'research': '研究',
    // work / projects
    'work': '工作', 'job': '工作', 'career': '事業', 'side': '副業',
    'project': '項目', 'projects': '項目', 'startup': '創業', 'business': '生意',
    'freelance': '接案', 'client': '客戶', 'clients': '客戶', 'meeting': '會議',
    'meetings': '會議', 'email': '電郵', 'admin': '行政',
    // home / life
    'home': '家務', 'house': '家務', 'chore': '家務', 'chores': '家務',
    'family': '家庭', 'personal': '個人', 'life': '生活', 'daily': '日常',
    'errand': '雜務', 'errands': '雜務', 'misc': '雜項', 'other': '其他',
    'shopping': '購物', 'grocery': '買餸', 'groceries': '買餸', 'cleaning': '清潔',
    'cooking': '煮食', 'food': '飲食', 'pet': '寵物', 'pets': '寵物',
    'garden': '園藝', 'plants': '植物',
    // health / fitness
    'health': '健康', 'fitness': '健身', 'gym': '健身', 'workout': '健身',
    'exercise': '運動', 'sport': '運動', 'sports': '運動', 'running': '跑步',
    'run': '跑步', 'yoga': '瑜伽', 'diet': '飲食', 'sleep': '睡眠',
    'meditation': '冥想', 'mental': '心理', 'wellness': '健康',
    // social / hobbies
    'club': '社團', 'clubs': '社團', 'society': '社團', 'social': '社交',
    'friend': '朋友', 'friends': '朋友', 'hobby': '興趣', 'hobbies': '興趣',
    'music': '音樂', 'art': '藝術', 'game': '遊戲', 'games': '遊戲',
    'gaming': '遊戲', 'reading': '閱讀', 'read': '閱讀', 'book': '書籍',
    'books': '書籍', 'movie': '電影', 'movies': '電影', 'travel': '旅行',
    'trip': '旅行', 'trips': '旅行', 'photography': '攝影', 'volunteer': '義工',
    // money
    'finance': '財務', 'finances': '財務', 'money': '財務', 'budget': '預算',
    'bills': '帳單', 'bill': '帳單', 'savings': '儲蓄', 'tax': '稅務',
    'taxes': '稅務', 'invest': '投資', 'investing': '投資',
    // planning
    'goal': '目標', 'goals': '目標', 'idea': '想法', 'ideas': '想法',
    'plan': '計劃', 'plans': '計劃', 'todo': '待辦', 'inbox': '收件',
    'someday': '將來', 'urgent': '緊急', 'today': '今日',
  };

  /// Best-effort Chinese label for a group name. Whole phrase first, then the
  /// first recognised word; blank if nothing matches.
  static String zhForName(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return '';
    if (_zhDict.containsKey(n)) return _zhDict[n]!;
    final words = n.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty);
    for (final w in words) {
      final hit = _zhDict[w];
      if (hit != null) return hit;
    }
    return '';
  }

  void deleteGroup(Group g) {
    if (groups.length <= 1) return;
    final dest = groups.firstWhere((x) => x.key != g.key).key;
    for (final t in tasks) {
      if (t.group == g.key) t.group = dest;
    }
    if (filter == g.key) filter = 'all';
    groups.remove(g);
    _changed();
  }

  // ---------- view ----------
  void setViewMode(String m) {
    viewMode = m;
    _changed();
  }

  void setFilter(String f) {
    filter = f;
    _changed();
  }

  void setShowDone(bool v) {
    showDone = v;
    _changed();
  }

  // ---------- due helpers ----------
  static DateTime? parseISO(String? iso) {
    if (iso == null) return null;
    final p = iso.split('-');
    if (p.length != 3) return null;
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  String? dueLabel(Task t) {
    final d = parseISO(t.dueISO);
    if (d == null) return null;
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final days = d.difference(t0).inDays;
    if (days < 0) return 'overdue';
    if (days == 0) return 'today';
    if (days == 1) return 'tmr';
    if (days < 7) {
      return ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.weekday % 7];
    }
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${mon[d.month - 1]}';
  }

  bool soon(Task t) {
    final d = parseISO(t.dueISO);
    if (d == null) return false;
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    return d.difference(t0).inDays <= 2;
  }
}

/// Global app store instance.
final store = CadenceStore();
