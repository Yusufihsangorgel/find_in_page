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
  ///
  /// Unlike a plain `TextField(autofocus: true)`, which only takes focus
  /// when nothing in the enclosing `FocusScope` already has it, this moves
  /// focus into the field regardless of what was focused before — a page
  /// with a focused list or a focused `TextField` still lands keyboard
  /// input in the query field. When this bar is later removed from the
  /// tree (the built-in bar on close, or any other widget that stops
  /// building it) while its field still has focus, Flutter returns focus to
  /// whatever held it before, the same way it would for any focused widget
  /// that disappears; if the user moved focus elsewhere first, it is left
  /// there. Pass false to leave focus alone in both directions.
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
    if (widget.autofocus) {
      // TextField's own autofocus only takes focus when the enclosing
      // FocusScope has none; requesting it directly here always wins, which
      // is the point — see the autofocus dartdoc. Restoring focus on the
      // way out needs no code of ours: disposing a FocusNode that still has
      // primary focus already asks Flutter to refocus whatever was focused
      // before it, via FocusNode.unfocus's default
      // UnfocusDisposition.previouslyFocusedChild — the same mechanism any
      // focused widget gets when it is removed from the tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
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
    // See the initState comment: if _focusNode still has primary focus here,
    // Flutter itself moves focus back to whatever held it before as part of
    // disposing a focused node, so there is nothing to do beyond disposing
    // it. If the user moved focus elsewhere first, this node no longer has
    // primary focus and nothing is moved.
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
                    // Focus is requested explicitly in initState instead of
                    // through this flag; see the autofocus dartdoc for why.
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
