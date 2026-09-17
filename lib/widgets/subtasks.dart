import 'package:flutter/material.dart';

import '../models.dart';
import '../palette.dart';
import '../store.dart';

/// A task's subtasks: tap a title to edit it inline (like the task title), and
/// a persistent add field at the bottom that adds on Enter and keeps focus so
/// several can be entered in a row.
class SubtaskSection extends StatefulWidget {
  final Task task;
  final Color color;
  const SubtaskSection({required this.task, required this.color});
  @override
  State<SubtaskSection> createState() => SubtaskSectionState();
}

class SubtaskSectionState extends State<SubtaskSection> {
  int? _editIndex;
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

  void _startEdit(int i, SubTask s) {
    setState(() {
      _editIndex = i;
      _editCtl.text = s.title;
      _editCtl.selection = TextSelection(baseOffset: 0, extentOffset: s.title.length);
    });
  }

  void _commitEdit(SubTask s) {
    if (_editIndex == null) return;
    store.renameSub(widget.task, s, _editCtl.text);
    setState(() => _editIndex = null);
  }

  void _add() {
    final v = _addCtl.text.trim();
    if (v.isEmpty) return;
    store.addSub(widget.task, v);
    _addCtl.clear();
    _addFocus.requestFocus(); // keep focus so you can add several in a row
  }

  TextField _editField(SubTask s) => TextField(
        controller: _editCtl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commitEdit(s),
        onTapOutside: (_) => _commitEdit(s),
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

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final color = widget.color;
    return Container(
      margin: const EdgeInsets.only(top: 10, left: 2),
      padding: const EdgeInsets.only(top: 9),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, s) in t.sub.indexed)
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
                child: _editIndex == i
                    ? _editField(s)
                    : GestureDetector(
                        onTap: () => _startEdit(i, s),
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
