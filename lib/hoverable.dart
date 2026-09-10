import 'package:flutter/material.dart';

/// Wraps a tappable child with a pointer cursor and a subtle hover highlight
/// (a faint dark tint), so plain GestureDetector-style controls get the same
/// feedback as the Material buttons on web/desktop.
class Hoverable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final Color hoverColor;
  const Hoverable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(7)),
    this.hoverColor = const Color(0x1F000000),
  });

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Stack(children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 110),
                opacity: _hover ? 1 : 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.hoverColor,
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
