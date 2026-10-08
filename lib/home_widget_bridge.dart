import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'models.dart';
import 'store.dart';

// Keep these in sync with the native side (CadenceWidgetProvider / service).
const _androidName = 'CadenceWidgetProvider';
const _qualifiedAndroidName = 'com.oliver.cadence.CadenceWidgetProvider';
const allDataKey = 'cadence_all'; // JSON: every task, active first then done
const focusDataKey = 'cadence_focus'; // JSON: focus (starred) tasks, same order

bool get _supported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Map<String, dynamic> _json(Task t) {
  final g = store.groupOf(t.group);
  return {
    'id': t.id,
    'title': t.title,
    'group': g.name,
    'color': g.color, // ARGB int
    'done': t.done,
    'star': t.star,
    // yyyy-MM-dd, so the widget can count "due today" itself (it redraws on
    // its own every 30 min, so the count rolls over at midnight).
    'due': _isoDay(CadenceStore.parseISO(t.dueISO)),
  };
}

String? _isoDay(DateTime? d) => d == null
    ? null
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Serialise both widget pages (All + Focus) and hand them to the widget.
Future<void> pushWallToWidget() async {
  if (!_supported) return;
  try {
    // All page: active tasks first, completed ones below. Dailies live in
    // their own section in-app and are kept off the widget.
    final all = <Task>[
      ...store.tasks.where((t) => !t.done && !t.daily),
      ...store.tasks.where((t) => t.done && !t.daily),
    ];
    // Focus page: only what's still to do, in wall order — a finished focus
    // task drops off rather than lingering struck-through.
    final focus = store.wallTasks();
    await HomeWidget.saveWidgetData<String>(
        allDataKey, jsonEncode(all.map(_json).toList()));
    await HomeWidget.saveWidgetData<String>(
        focusDataKey, jsonEncode(focus.map(_json).toList()));
    await HomeWidget.updateWidget(
      androidName: _androidName,
      qualifiedAndroidName: _qualifiedAndroidName,
    );
  } catch (_) {
    // Widget storage unavailable (e.g. no widget added yet) — ignore.
  }
}

/// Runs in a background isolate when a widget row is tapped:
///   `cadence://toggle?id=N`  -> mark done / undone
///   `cadence://star?id=N`    -> add to / remove from the Focus wall
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (uri == null) return;
  final id = int.tryParse(uri.queryParameters['id'] ?? '');
  if (id == null) return;
  await store.load();
  final matches = store.tasks.where((x) => x.id == id);
  if (matches.isEmpty) return;
  final t = matches.first;
  switch (uri.host) {
    case 'toggle':
      store.toggleDone(t);
      break;
    case 'star':
      store.toggleStar(t);
      break;
  }
  await pushWallToWidget();
}

/// Registers the tap callback and seeds the widget with the current data.
/// Also mirrors every future store change onto the widget.
Future<void> initHomeWidget() async {
  if (!_supported) return;
  try {
    await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    await pushWallToWidget();
    // Coalesce bursts: this fires on every store change, and a sync merge can
    // emit many in a row. Each push re-serialises every task and crosses the
    // platform channel, so doing it per notification is pure waste.
    Timer? debounce;
    store.addListener(() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 800), pushWallToWidget);
    });
  } catch (_) {}
}
