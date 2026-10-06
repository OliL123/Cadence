import 'package:flutter/services.dart';

/// In the phone app there's no file download, so CSVs go through the
/// clipboard: copy to export (paste into a spreadsheet), paste to import.
const bool csvIoUsesFiles = false;

Future<void> saveTextFile(String name, String text) =>
    Clipboard.setData(ClipboardData(text: text));

Future<List<String>> pickTextFiles() async {
  final d = await Clipboard.getData(Clipboard.kTextPlain);
  final t = d?.text;
  return (t == null || t.trim().isEmpty) ? <String>[] : [t];
}

/// No browser to hand off to; copying the link is the useful fallback.
void openLink(String url) => Clipboard.setData(ClipboardData(text: url));
