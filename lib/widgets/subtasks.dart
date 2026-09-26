import 'package:flutter/material.dart';

import '../models.dart';
import '../palette.dart';
import '../store.dart';

/// A task's subtasks: drag the handle to reorder, tap a title to edit it
/// inline (like the task title), and a persistent add field at the bottom that
/// adds on Enter and keeps focus so several can be entered in a row.
class SubtaskSection extends StatefulWidget {
  final Task task;
  final Color color;
  const SubtaskSection({required this.task, required this.color});
  @override
  State<SubtaskSection> createState() => SubtaskSectionState();
}

class SubtaskSectionState extends State<SubtaskSection> {
  // The subtask being edited, by identity rather than position: rows move when
  // they're reordered (or when a sync lands), and an index would then point the
  // editor at a different subtask.
  SubTask? _editing;
  final _editCtl = TextEditingController();
  final _addCtl = TextEditingController();
  final _addFocus = FocusNode();

  @override
  void dispose() {
    _editCtl.dispose();
    _addCtl.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _startEdit(SubTask s) {
    setState(() {
      _editing = s;
      _editCtl.text = s.title;
      _editCtl.selection = TextSelection(baseOffset: 0, extentOffset: s.title.length);
    });
  }

  void _commitEdit() {
    final s = _editing;
    if (s == null) return;
    store.renameSub(widget.task, s, _editCtl.text);
    setState(() => _editing = null);
  }

  void _add() {
    final v = _addCtl.text.trim();
    if (v.isEmpty) return;
    store.addSub(widget.task, v);
    _addCtl.clear();
    _addFocus.requestFocus(); // keep focus so you can add several in a row
  }

  TextField _editField() => TextField(
        controller: _editCtl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commitEdit(),
        onTapOutside: (_) => _commitEdit(),
        style: const TextStyle(fontSize: 13, color: C.ink),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: C.paper,
          contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: C.mustard, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: C.mustard, width: 1.5)),
        ),
      );

  Widget _row(Task t, int i, SubTask s, bool movable) {
    final color = widget.color;
    return Padding(
      key: ObjectKey(s),
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        if (movable)
          // The handle starts a drag at once (mouse or touch). Only the handle
          // does, so tapping a title still edits it and swiping still scrolls.
          ReorderableDragStartListener(
            index: i,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.drag_indicator, size: 16, color: C.ink3),
              ),
            ),
          ),
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
          child: identical(_editing, s)
              ? _editField()
              : GestureDetector(
                  onTap: () => _startEdit(s),
                  behavior: HitTestBehavior.opaque,
                  child: Text(s.title,
                      style: TextStyle(
                        fontSize: 13,
                        color: s.done ? C.ink3 : C.ink,
                        decoration: s.done ? TextDecoration.lineThrough : null,
                      )),
                ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => store.deleteSub(t, s),
          child: const Icon(Icons.close, size: 14, color: C.ink3),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final movable = t.sub.length > 1;
    return Container(
      margin: const EdgeInsets.only(top: 10, left: 2),
      padding: const EdgeInsets.only(top: 9),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (t.sub.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: t.sub.length,
            // Settle an open title edit before rows start moving.
            onReorderStart: (_) => _commitEdit(),
            onReorderItem: (from, to) => store.reorderSub(t, from, to),
            proxyDecorator: (child, _, __) => Material(
              color: C.paper2,
              elevation: 3,
              borderRadius: BorderRadius.circular(6),
              child: child,
            ),
            itemBuilder: (_, i) => _row(t, i, t.sub[i], movable),
          ),
        Row(children: [
          const Icon(Icons.add, size: 16, color: C.greenD),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _addCtl,
              focusNode: _addFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              style: const TextStyle(fontSize: 13, color: C.ink),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'add subtask…',
                hintStyle: TextStyle(fontSize: 13, color: C.ink3),
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
