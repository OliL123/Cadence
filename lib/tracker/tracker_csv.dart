// CSV in and out for the Career section, using the plan's column names so the
// files round-trip through Excel / Google Sheets.
import 'tracker_models.dart';

/// Excel only reads a CSV as UTF-8 (em dashes, accents) when it starts with a
/// byte-order mark.
const _bom = '﻿';

String _cell(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(RegExp(r'[",\r\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _encode(List<String> columns, Iterable<Map<String, dynamic>> rows) {
  final b = StringBuffer(_bom)..write(columns.join(','));
  for (final r in rows) {
    b.write('\r\n');
    b.write(columns.map((c) => _cell(r[c])).join(','));
  }
  b.write('\r\n');
  return b.toString();
}

String applicationsToCsv(List<Application> apps) =>
    _encode(Application.csvColumns, apps.map((a) => a.toJson()));

String eventsToCsv(List<TrackEvent> events) =>
    _encode(TrackEvent.csvColumns, events.map((e) => e.toJson()));

/// RFC 4180 parse: quoted fields may hold commas, doubled quotes and line
/// breaks. Returns one map per data row, keyed by the (lower-cased) header.
List<Map<String, String>> parseCsv(String text) {
  if (text.startsWith(_bom)) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  rows.removeWhere((r) => r.every((c) => c.trim().isEmpty));
  if (rows.isEmpty) return [];
  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  return [
    for (final r in rows.skip(1))
      {for (var c = 0; c < header.length; c++) header[c]: c < r.length ? r[c] : ''}
  ];
}

/// What a CSV holds, judged by its header.
enum CsvKind { applications, events, unknown }

CsvKind csvKind(List<Map<String, String>> rows) {
  if (rows.isEmpty) return CsvKind.unknown;
  final keys = rows.first.keys.toSet();
  if (keys.contains('company')) return CsvKind.applications;
  if (keys.contains('name') && keys.contains('type')) return CsvKind.events;
  return CsvKind.unknown;
}

Map<String, dynamic> _withIntId(Map<String, String> r) =>
    {...r, 'id': int.tryParse(r['id'] ?? '')};

List<Application> applicationsFromCsv(List<Map<String, String>> rows) => [
      for (final r in rows)
        if ((r['company'] ?? '').trim().isNotEmpty) Application.fromJson(_withIntId(r))
    ];

List<TrackEvent> eventsFromCsv(List<Map<String, String>> rows) => [
      for (final r in rows)
        if ((r['name'] ?? '').trim().isNotEmpty) TrackEvent.fromJson(_withIntId(r))
    ];
