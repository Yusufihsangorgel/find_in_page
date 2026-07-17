import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'scope.dart';

/// A `Text` replacement whose content participates in find-in-page.
///
/// Registers itself with the enclosing [FindInPageScope]'s controller (or
/// an explicitly passed [controller]) and renders highlights over matches
/// of the current query. The active match gets [activeHighlightColor].
///
/// Supports the common `Text` parameters. Matches inside content clipped
/// away by [maxLines]/[overflow] are still counted and navigated to, but
/// cannot become visible.
class FindableText extends StatefulWidget {
  /// Creates searchable text.
  const FindableText(
    this.data, {
    super.key,
    this.controller,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    this.highlightColor = const Color(0xFFFFF59D),
    this.activeHighlightColor = const Color(0xFFFFB74D),
  });

  /// The text to display and search in.
  final String data;

  /// Explicit controller. When null, the controller is looked up from the
  /// nearest [FindInPageScope].
  final FindInPageController? controller;

  /// See [Text.style].
  final TextStyle? style;

  /// See [Text.strutStyle].
  final StrutStyle? strutStyle;

  /// See [Text.textAlign].
  final TextAlign? textAlign;

  /// See [Text.textDirection].
  final TextDirection? textDirection;

  /// See [Text.locale].
  final Locale? locale;

  /// See [Text.softWrap].
  final bool? softWrap;

  /// See [Text.overflow].
  final TextOverflow? overflow;

  /// See [Text.textScaler].
  final TextScaler? textScaler;

  /// See [Text.maxLines].
  final int? maxLines;

  /// See [Text.semanticsLabel].
  final String? semanticsLabel;

  /// See [Text.textWidthBasis].
  final TextWidthBasis? textWidthBasis;

  /// See [Text.textHeightBehavior].
  final TextHeightBehavior? textHeightBehavior;

  /// See [Text.selectionColor].
  final Color? selectionColor;

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
    if (controller == null) return _text(widget.data);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final matches = controller.matchesFor(this);
        final spans = <InlineSpan>[];
        var cursor = 0;
        for (final match in matches) {
          // A text change invalidates offsets until the controller's
          // deferred recompute runs after this frame; skip anything that
          // no longer fits instead of crashing on substring.
          if (match.end > widget.data.length) continue;
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
        if (spans.isEmpty) return _text(widget.data);
        if (cursor < widget.data.length) {
          spans.add(TextSpan(text: widget.data.substring(cursor)));
        }
        return Text.rich(
          TextSpan(style: widget.style, children: spans),
          strutStyle: widget.strutStyle,
          textAlign: widget.textAlign,
          textDirection: widget.textDirection,
          locale: widget.locale,
          softWrap: widget.softWrap,
          overflow: widget.overflow,
          textScaler: widget.textScaler,
          maxLines: widget.maxLines,
          semanticsLabel: widget.semanticsLabel,
          textWidthBasis: widget.textWidthBasis,
          textHeightBehavior: widget.textHeightBehavior,
          selectionColor: widget.selectionColor,
        );
      },
    );
  }

  Text _text(String data) => Text(
        data,
        style: widget.style,
        strutStyle: widget.strutStyle,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        locale: widget.locale,
        softWrap: widget.softWrap,
        overflow: widget.overflow,
        textScaler: widget.textScaler,
        maxLines: widget.maxLines,
        semanticsLabel: widget.semanticsLabel,
        textWidthBasis: widget.textWidthBasis,
        textHeightBehavior: widget.textHeightBehavior,
        selectionColor: widget.selectionColor,
      );
}
