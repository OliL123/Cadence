import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../tracker/tracker_models.dart' show safeWebLink;

/// On the web, CSVs are real files: download to save, file picker to load.
const bool csvIoUsesFiles = true;

/// Download [text] as [name].
Future<void> saveTextFile(String name, String text) async {
  final blob = web.Blob(
      [text.toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// Let the user pick one or more CSV files; returns their contents (empty if
/// they cancelled).
Future<List<String>> pickTextFiles() {
  final done = Completer<List<String>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,text/csv'
    ..multiple = true;
  // A callback handed to JS can't return a Future, so it only starts the read.
  input.addEventListener(
      'change', ((web.Event _) { unawaited(_readAll(input, done)); }).toJS);
  input.addEventListener(
      'cancel', ((web.Event _) { if (!done.isCompleted) done.complete(<String>[]); }).toJS);
  input.click();
  return done.future;
}

Future<void> _readAll(web.HTMLInputElement input, Completer<List<String>> done) async {
  final out = <String>[];
  final files = input.files;
  if (files != null) {
    for (var i = 0; i < files.length; i++) {
      out.add((await files.item(i)!.text().toDart).toDart);
    }
  }
  if (!done.isCompleted) done.complete(out);
}

/// Open a posting link in a new tab — web links only. Links come from forms,
/// CSV imports and (later) emails, so a `javascript:` or `data:` link must
/// never run: opened from here it would execute inside Cadence and could read
/// the sign-in session. `noopener` stops the opened page reaching back into
/// this tab (e.g. to swap it for a look-alike login page).
void openLink(String url) {
  final safe = safeWebLink(url);
  if (safe != null) web.window.open(safe, '_blank', 'noopener,noreferrer');
}
