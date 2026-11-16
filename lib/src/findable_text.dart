import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'auto_discovery.dart';
import 'controller.dart';
import 'exclude_from_find.dart';
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
final class FindableText extends StatefulWidget {
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

class _FindableTextState extends State<FindableText>
    implements FindableSource, MatchRectangleReveal {
  FindInPageController? _controller;

  @override
  String get findableText => widget.data;

  @override
  BuildContext? get findableContext => mounted ? context : null;

  @override
  void showMatchOnScreen(int start, int end, {Rect? bar}) {
    final paragraph = _paragraph();
    if (paragraph == null) return;
    // The rendered paragraph holds exactly [findableText]. Discovered text
    // gets the same reveal.
    final revealed = showTextOnScreen(
      ParagraphSource(paragraph),
      start,
      end,
      bar: bar,
    );
    if (revealed == null) return;
    _showInFixedScrollViews(paragraph, revealed.match, revealed.shown);
  }

  /// Moves a `PageView` around this text, or a scroll view under
  /// `NeverScrollableScrollPhysics`, until the match is inside it.
  ///
  /// [RenderObject.showOnScreen] passes over a view that does not scroll
  /// implicitly. A user may have no way to scroll one, and a match left
  /// outside it could never be seen. A `PageView` with `allowImplicitScrolling`
  /// is scrolled there, but only as far as the match needs. It then settles on
  /// the nearest page, and that can be the page next to the match. A view
  /// under `NeverScrollableScrollPhysics` that does not already show [shown]
  /// whole, or a `PageView` that does not show [match], is moved to put
  /// [match] in its middle. A `PageView` then settles on the page holding the
  /// match. It cannot move a match within the page it shows, and leaves that
  /// page in place. Both rectangles are in the coordinates of [paragraph].
  ///
  /// A scroll view between the text and such a view brings the match inside
  /// its own bounds, by itself or moved here. The view around it only has to
  /// show that part of it, as `Scrollable.ensureVisible` does. A tab holding
  /// a sideways row of chips stays on screen, and so does a page holding a
  /// list or a table.
  void _showInFixedScrollViews(RenderBox paragraph, Rect match, Rect shown) {
    RenderObject target = paragraph;
    RenderAbstractViewport? inner;
    // The axes [inner] scrolls along. The two scroll views of a
    // two-dimensional view share its viewport, one for each axis.
    final innerAxes = <Axis>{};
    for (
      var scrollable = context.findAncestorStateOfType<ScrollableState>();
      scrollable != null;
      scrollable = scrollable.context.findAncestorStateOfType<ScrollableState>()
    ) {
      final position = scrollable.position;
      if (!position.hasPixels) continue;
      final viewport = _viewportOf(scrollable, paragraph);
      if (viewport == null) continue;
      if (inner != null && !identical(inner, viewport)) {
        final transform = target.getTransformTo(inner);
        final bounds = inner.paintBounds;
        match = _moveInto(
          bounds,
          MatrixUtils.transformRect(transform, match),
          innerAxes,
        );
        shown = _moveInto(
          bounds,
          MatrixUtils.transformRect(transform, shown),
          innerAxes,
        );
        target = inner;
        innerAxes.clear();
      }
      inner = viewport;
      innerAxes.add(position.axis);
      final paged = _snapsToPages(position.physics);
      if (position.allowImplicitScrolling && !paged) continue;
      RevealedOffset reveal(double alignment, Rect rect) =>
          viewport.getOffsetToReveal(
            target,
            alignment,
            rect: rect,
            axis: position.axis,
          );
      // A view that settles on whole pages cannot move a match within the
      // page it shows. Only a match outside that page is worth a move.
      final wanted = paged ? match : shown;
      final hidden = RevealedOffset.clampOffset(
        leadingEdgeOffset: reveal(0, wanted),
        trailingEdgeOffset: reveal(1, wanted),
        currentOffset: position.pixels,
      );
      if (hidden == null) continue;
      position.moveTo(
        reveal(0.5, match).offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  /// [rect] moved along each of [axes] until it is inside [bounds]. Along an
  /// axis where it is longer than [bounds], it starts where they start.
  ///
  /// Along an axis the view does not scroll, [rect] stays put. The margin
  /// above and below a match in a sideways row reaches past the row, and the
  /// view around the row still has to keep that margin clear of the bar.
  static Rect _moveInto(Rect bounds, Rect rect, Set<Axis> axes) {
    double shift(double start, double end, double min, double max) {
      if (end - start >= max - min || start < min) return min - start;
      if (end > max) return max - end;
      return 0;
    }

    return rect.translate(
      axes.contains(Axis.horizontal)
          ? shift(rect.left, rect.right, bounds.left, bounds.right)
          : 0,
      axes.contains(Axis.vertical)
          ? shift(rect.top, rect.bottom, bounds.top, bounds.bottom)
          : 0,
    );
  }

  /// Whether [physics] settles its scroll view on a whole page, as a
  /// `PageView` does.
  static bool _snapsToPages(ScrollPhysics physics) {
    for (ScrollPhysics? node = physics; node != null; node = node.parent) {
      if (node is PageScrollPhysics) return true;
    }
    return false;
  }

  /// The viewport [scrollable] scrolls, found among the ancestors of
  /// [paragraph], or null.
  ///
  /// It is the highest viewport below the scrollable's own render object.
  /// Viewports further down belong to scroll views nested inside it.
  static RenderAbstractViewport? _viewportOf(
    ScrollableState scrollable,
    RenderObject paragraph,
  ) {
    final root = scrollable.context.findRenderObject();
    RenderAbstractViewport? found;
    for (var node = paragraph.parent; node != null; node = node.parent) {
      if (identical(node, root)) return found;
      if (node is RenderAbstractViewport) found = node;
    }
    return null;
  }

  /// The paragraph [build] rendered, or null when there is none.
  RenderParagraph? _paragraph() {
    if (!mounted) return null;
    RenderParagraph? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is RenderObjectElement) {
        final renderObject = element.renderObject;
        if (renderObject is RenderParagraph) {
          found = renderObject;
          return;
        }
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

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
    // This widget reports its own text to the controller and highlights it by
    // restyling its own spans, so automatic discovery must not read it again.
    if (controller == null) {
      return ExcludeFromFind(child: _text(widget.data));
    }
    return ExcludeFromFind(
      child: ListenableBuilder(
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
                TextSpan(text: widget.data.substring(cursor, match.start)),
              );
            }
            spans.add(
              TextSpan(
                text: widget.data.substring(match.start, match.end),
                style: TextStyle(
                  backgroundColor: controller.isActive(match)
                      ? widget.activeHighlightColor
                      : widget.highlightColor,
                ),
              ),
            );
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
      ),
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
