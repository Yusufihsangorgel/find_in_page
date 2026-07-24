import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';

/// A compact Material find bar: query field, match counter, and
/// previous/next/close buttons. Enter jumps to the next match; Escape
/// invokes [onClose].
///
/// Used by `FindInPageScope` out of the box; embed it yourself for custom
/// placement.
final class FindBar extends StatefulWidget {
  /// Creates a find bar driving [controller].
  const FindBar({
    required this.controller,
    this.onClose,
    this.autofocus = true,
    this.hintText = 'Find in page',
    this.previousTooltip = 'Previous match',
    this.nextTooltip = 'Next match',
    this.closeTooltip = 'Close',
    this.matchStatusLabel = _defaultMatchStatusLabel,
    super.key,
  });

  /// The controller this bar reads and drives.
  final FindInPageController controller;

  /// Called when the close button or Escape is pressed.
  final VoidCallback? onClose;

  /// Whether the query field grabs focus when the bar appears.
  final bool autofocus;

  /// Placeholder text for the query field.
  final String hintText;

  /// Tooltip for the previous-match button.
  final String previousTooltip;

  /// Tooltip for the next-match button.
  final String nextTooltip;

  /// Tooltip for the close button.
  final String closeTooltip;

  /// Builds what a screen reader announces when the match count changes,
  /// from the active match index (zero-based, `-1` when there is none) and
  /// the total.
  ///
  /// The counter beside the field is the whole feedback loop of a find bar:
  /// a sighted user watches it move while typing. It is announced as a live
  /// region so it reaches a screen reader too, since focus stays in the query
  /// field and never lands on the counter itself. The visible `3/12` is left
  /// out of the announcement because it reads badly aloud.
  ///
  /// Defaults to English, as the tooltips above do; pass a localized builder:
  ///
  /// ```dart
  /// matchStatusLabel: (active, count) => count == 0
  ///     ? l10n.noMatches
  ///     : l10n.matchOf(active + 1, count),
  /// ```
  final String Function(int activeIndex, int matchCount) matchStatusLabel;

  static String _defaultMatchStatusLabel(int activeIndex, int matchCount) =>
      matchCount == 0
          ? 'No matches'
          : 'Match ${activeIndex + 1} of $matchCount';

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.query);
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(FindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Reflects programmatic `search`/`clearSearch` calls in the field,
  /// without fighting the user while they are typing.
  void _syncFromController() {
    if (!_focusNode.hasFocus && _text.text != widget.controller.query) {
      _text.text = widget.controller.query;
    }
  }

  void _submit(String _) {
    widget.controller.next();
    // Keep typing/navigating without re-clicking the field.
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        if (widget.onClose != null)
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose!,
      },
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 96, maxWidth: 180),
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
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  if (widget.controller.query.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final count = widget.controller.matchCount;
                  final active = widget.controller.activeMatchIndex;
                  return Semantics(
                    liveRegion: true,
                    label: widget.matchStatusLabel(active ?? -1, count),
                    child: ExcludeSemantics(
                      child: Text(
                        count == 0 ? '0/0' : '${active! + 1}/$count',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: widget.previousTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: widget.controller.previous,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: widget.nextTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: widget.controller.next,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: widget.closeTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
