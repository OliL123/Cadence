import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

/// Local reminders for tasks that have both a due date and a due time. Android
/// only; a no-op on web/desktop. Everything is wrapped in try/catch so a
/// failure never breaks the app.
class Reminders {
  Reminders._();
  static final Reminders instance = Reminders._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!_supported) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));
      final impl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await impl?.requestNotificationsPermission();
      _ready = true;
      await sync();
      store.addListener(sync);
    } catch (_) {}
  }

  /// Cancel and re-schedule reminders for every future dated+timed task.
  Future<void> sync() async {
    if (!_supported || !_ready) return;
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'cadence_tasks',
          'Task reminders',
          channelDescription: 'Reminders for tasks with a due time',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      for (final t in store.tasks) {
        if (t.done || t.daily) continue;
        final d = CadenceStore.parseISO(t.dueISO);
        if (d == null) continue;

        DateTime when;
        String body;
        final hm = t.dueTime?.split(':');
        if (hm != null && hm.length == 2) {
          // Timed: remind one hour before it's due.
          final due = DateTime(
              d.year, d.month, d.day, int.tryParse(hm[0]) ?? 0, int.tryParse(hm[1]) ?? 0);
          when = due.subtract(const Duration(hours: 1));
          body = '一小時後到期 · due in an hour';
        } else {
          // Date only: remind at 7am on the day it's due.
          when = DateTime(d.year, d.month, d.day, 7, 0);
          body = '今日到期 · due today';
        }
        if (!when.isAfter(now)) continue;
        // Schedule at the exact UTC instant of the local time — avoids needing a
        // device-timezone plugin while still firing at the right wall-clock time.
        await _plugin.zonedSchedule(
          t.id,
          t.title,
          body,
          tz.TZDateTime.from(when.toUtc(), tz.UTC),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {}
  }
}
