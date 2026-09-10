import 'palette.dart';

/// Skin-aware label strings. Cadence uses bilingual Cantonese/English; Chronicle
/// uses classical English with a little Latin flavour. All chosen at build time.
///
/// `zh` slots hold the secondary script shown beside a Latin word (Chinese in
/// Cadence, italic Latin in Chronicle). An empty string means "hide it".
class L {
  static const bool _c = C.chronicle;

  // masthead
  static const appName = _c ? 'CHRONICLE' : 'CADENCE';
  static const appZh = _c ? '' : '節奏';
  static const madeFor = _c ? 'PRO · ME — ANNO MMXXVI' : '香港製造 · MADE FOR ME';

  // tasks panel
  static const tasks = _c ? 'THE LEDGER' : 'TASKS';
  static const tasksZh = _c ? 'entrata' : '待辦';
  static const focusName = _c ? 'The Spread' : '麻雀'; // referenced in the caption
  static const dueSoon = _c ? 'DUE SOON' : 'DUE SOON';
  static const dueSoonZh = _c ? 'imminentia' : '就到期';

  // groups / sections
  static const groups = _c ? 'GROUPS' : 'GROUPS';
  static const groupsZh = _c ? 'ordines' : '分類';
  static const done = _c ? 'Done' : 'Done';
  static const doneZh = _c ? 'peracta' : '完成';
  static const daily = _c ? 'DAILY' : 'DAILY';
  static const dailyZh = _c ? 'cotidie' : '每日';

  // controls
  static const add = _c ? 'Add' : '新增';
  static const sync = _c ? 'SYNC' : 'SYNC';
  static const syncZh = _c ? 'nexus' : '雲端同步';
  static const pri = _c ? 'NB' : '急'; // priority badge glyph

  // mobile bottom nav (zh slot + en)
  static const navTasksZh = _c ? '' : '待辦';
  static const navTasksEn = _c ? 'LEDGER' : 'TASKS';
  static const navFocusZh = _c ? '' : '麻雀';
  static const navFocusEn = _c ? 'SPREAD' : 'FOCUS';
}
