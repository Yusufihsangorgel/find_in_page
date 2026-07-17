import 'package:flutter/material.dart';

import 'controller.dart';

/// A compact Material find bar: query field, match counter, and
/// previous/next/close buttons. Enter jumps to the next match.
///
/// Used by `FindInPageScope` out of the box; embed it yourself for custom
/// placement.
class FindBar extends StatefulWidget {
  const FindBar({
    required this.controller,
    this.onClose,
    this.autofocus = true,
    this.hintText = 'Find in page',
    super.key,
  });

  final FindInPageController controller;

  /// Called when the close button is pressed.
  final VoidCallback? onClose;

  /// Whether the query field grabs focus when the bar appears.
  final bool autofocus;

  final String hintText;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.query);
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String _) {
    widget.controller.next();
    // Keep typing/navigating without re-clicking the field.
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: _text,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  isDense: true,
                  border: InputBorder.none,
                ),
                onChanged: widget.controller.search,
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final count = widget.controller.matchCount;
                final active = widget.controller.activeMatchIndex;
                return Text(
                  count == 0 ? '0/0' : '${active! + 1}/$count',
                  style: theme.textTheme.bodySmall,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: 'Previous match',
              visualDensity: VisualDensity.compact,
              onPressed: widget.controller.previous,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Next match',
              visualDensity: VisualDensity.compact,
              onPressed: widget.controller.next,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}
