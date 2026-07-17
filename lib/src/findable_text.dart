import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'scope.dart';

/// A `Text` replacement whose content participates in find-in-page.
///
/// Registers itself with the enclosing [FindInPageScope]'s controller (or
/// an explicitly passed [controller]) and renders highlights over matches
/// of the current query. The active match gets [activeHighlightColor].
class FindableText extends StatefulWidget {
  const FindableText(
    this.data, {
    super.key,
    this.controller,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.highlightColor = const Color(0xFFFFF59D),
    this.activeHighlightColor = const Color(0xFFFFB74D),
  });

  /// The text to display and search in.
  final String data;

  /// Explicit controller. When null, the controller is looked up from the
  /// nearest [FindInPageScope].
  final FindInPageController? controller;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Background color for inactive matches.
  final Color highlightColor;

  /// Background color for the active match.
  final Color activeHighlightColor;

  @override
  State<FindableText> createState() => _FindableTextState();
}

class _FindableTextState extends State<FindableText> implements FindableSource {
  FindInPageController? _controller;

  @override
  String get findableText => widget.data;

  @override
  BuildContext? get findableContext => mounted ? context : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveController();
  }

  @override
  void didUpdateWidget(FindableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _resolveController();
    }
    if (oldWidget.data != widget.data) {
      _controller?.sourceTextChanged(this);
    }
  }

  void _resolveController() {
    final next = widget.controller ?? FindInPageScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.unregister(this);
    _controller = next;
    _controller?.register(this);
  }

  @override
  void dispose() {
    _controller?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _plainText();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final matches = controller.matchesFor(this);
        if (matches.isEmpty) return _plainText();
        final spans = <InlineSpan>[];
        var cursor = 0;
        for (final match in matches) {
          if (match.start > cursor) {
            spans.add(
                TextSpan(text: widget.data.substring(cursor, match.start)));
          }
          spans.add(TextSpan(
            text: widget.data.substring(match.start, match.end),
            style: TextStyle(
              backgroundColor: controller.isActive(match)
                  ? widget.activeHighlightColor
                  : widget.highlightColor,
            ),
          ));
          cursor = match.end;
        }
        if (cursor < widget.data.length) {
          spans.add(TextSpan(text: widget.data.substring(cursor)));
        }
        return Text.rich(
          TextSpan(style: widget.style, children: spans),
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
        );
      },
    );
  }

  Text _plainText() => Text(
        widget.data,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
}
