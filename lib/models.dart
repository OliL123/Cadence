import 'package:flutter/material.dart';
import 'palette.dart';

class SubTask {
  String title;
  bool done;
  SubTask(this.title, {this.done = false});
  Map<String, dynamic> toJson() => {'t': title, 'd': done};
  factory SubTask.fromJson(Map<String, dynamic> j) =>
      SubTask(j['t'] ?? '', done: j['d'] ?? false);
}

/// A mahjong tile. suit: 'm' (萬), 'p' (筒), 's' (索), 'z' (honor).
/// For honors, val 1=中 2=發 3=白.
class Tile {
  String suit;
  int val;
  Tile(this.suit, this.val);
  bool get isDragon => suit == 'z';
  Map<String, dynamic> toJson() => {'s': suit, 'v': val};
  factory Tile.fromJson(Map<String, dynamic> j) => Tile(j['s'] ?? 'm', j['v'] ?? 1);
}

class Task {
  int id;
  String title;
  String group;
  bool done;
  bool star;
  bool pri;
  String? dueISO; // yyyy-mm-dd
  String? dueTime; // HH:mm (24h), optional
  List<SubTask> sub;
  bool open; // subtask panel expanded
  Tile? tile; // its mahjong tile while on the focus wall
  int? doneAt; // ms-since-epoch when it was completed (for auto-clean)

  Task({
    required this.id,
    required this.title,
    required this.group,
    this.done = false,
    this.star = false,
    this.pri = false,
    this.dueISO,
    this.dueTime,
    List<SubTask>? sub,
    this.open = false,
    this.tile,
    this.doneAt,
  }) : sub = sub ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        'g': group,
        'done': done,
        'star': star,
        'pri': pri,
        'due': dueISO,
        'dueT': dueTime,
        'sub': sub.map((s) => s.toJson()).toList(),
        'open': open,
        'tile': tile?.toJson(),
        'doneAt': doneAt,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] ?? 0,
        title: j['t'] ?? '',
        group: j['g'] ?? '',
        done: j['done'] ?? false,
        star: j['star'] ?? false,
        pri: j['pri'] ?? false,
        dueISO: j['due'],
        dueTime: j['dueT'],
        sub: ((j['sub'] ?? []) as List)
            .map((e) => SubTask.fromJson(e as Map<String, dynamic>))
            .toList(),
        open: j['open'] ?? false,
        tile: j['tile'] == null ? null : Tile.fromJson(j['tile'] as Map<String, dynamic>),
        doneAt: j['doneAt'],
      );
}

class Group {
  String key;
  String name;
  String zh;
  int color;
  Group({required this.key, required this.name, required this.zh, required this.color});
  Color get c => Color(color);
  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'zh': zh, 'color': color};
  factory Group.fromJson(Map<String, dynamic> j) => Group(
        key: j['key'] ?? '',
        name: j['name'] ?? '',
        zh: j['zh'] ?? '',
        color: j['color'] ?? 0xFF888888,
      );
}

List<Group> defaultGroups() => [
      Group(key: 'uni', name: 'Uni', zh: '學業', color: C.navy.toARGB32()),
      Group(key: 'side', name: 'Side project', zh: '副業', color: C.red.toARGB32()),
      Group(key: 'home', name: 'Home', zh: '家務', color: C.mustard.toARGB32()),
      Group(key: 'health', name: 'Health', zh: '健康', color: C.green.toARGB32()),
      Group(key: 'errand', name: 'Errands', zh: '雜務', color: C.teal.toARGB32()),
    ];
