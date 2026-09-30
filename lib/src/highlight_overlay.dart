import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'auto_discovery.dart';
import 'controller.dart';

/// Paints match highlights over text the application never wrapped.
///
/// `FindableText` highlights by restyling its own spans, which is sharper and
/// composes with the text's own decoration. That is not available for text
/// belonging to widgets we do not own, so those matches are drawn on top
/// instead, as a browser draws its own find highlights.
///
/// Sits directly above the searched subtree and therefore has to do its own
/// clipping. Before painting a match it works out where the text is visible,
/// by walking from the text's render object up to this layer and intersecting
/// the clip each ancestor reports. A match scrolled out of a viewport, or
/// hidden by any other clip above it, paints nothing. A match cut by a clip
/// paints only the part that shows.
final class HighlightOverlay extends StatefulWidget {
  /// Wraps [child] in a layer that paints highlights for [controller].
  const HighlightOverlay({
    required this.controller,
    required this.color,
    required this.activeColor,
    required this.child,
    super.key,
  });

  /// The session whose matches are painted.
  final FindInPageController controller;

  /// Fill for matches that are not active.
  final Color color;

  /// Fill for the active match.
  final Color activeColor;

  /// The searched subtree.
  final Widget child;

  @override
  State<HighlightOverlay> createState() => _HighlightOverlayState();
}

class _HighlightOverlayState extends State<HighlightOverlay> {
  final GlobalKey _layerKey = GlobalKey();

  /// Repaints when the text underneath moves.
  ///
  /// The rectangles are read from render objects inside scroll viewports, but
  /// this layer sits above those viewports, so scrolling moves the text without
  /// dirtying us. Scroll notifications bubble up through here, which covers it
  /// without repainting on every frame.
  bool _onScroll(ScrollNotification notification) {
    if (widget.controller.discoveredSources.isNotEmpty) {
      _layerKey.currentContext?.findRenderObject()?.markNeedsPaint();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: _HighlightLayer(
        key: _layerKey,
        controller: widget.controller,
        color: widget.color,
        activeColor: widget.activeColor,
        child: widget.child,
      ),
    );
  }
}

class _HighlightLayer extends SingleChildRenderObjectWidget {
  const _HighlightLayer({
    required this.controller,
    required this.color,
    required this.activeColor,
    required super.child,
    super.key,
  });

  final FindInPageController controller;
  final Color color;
  final Color activeColor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderHighlightOverlay(
        controller: controller,
        color: color,
        activeColor: activeColor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHighlightOverlay renderObject,
  ) {
    renderObject
      ..controller = controller
      ..color = color
      ..activeColor = activeColor;
  }
}

/// The render object behind [HighlightOverlay].
class RenderHighlightOverlay extends RenderProxyBox {
  /// Creates a layer painting [controller]'s matches.
  RenderHighlightOverlay({
    required FindInPageController controller,
    required Color color,
    required Color activeColor,
  })  : _controller = controller,
        _color = color,
        _activeColor = activeColor {
    _controller.addListener(markNeedsPaint);
  }

  FindInPageController _controller;
  Color _color;
  Color _activeColor;

  /// The session whose matches are painted.
  set controller(FindInPageController value) {
    if (identical(value, _controller)) return;
    _controller.removeListener(markNeedsPaint);
    _controller = value;
    _controller.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// Fill for matches that are not active.
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  /// Fill for the active match.
  set activeColor(Color value) {
    if (value == _activeColor) return;
    _activeColor = value;
    markNeedsPaint();
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    super.detach();
  }

  /// Where [source] is visible, in this layer's coordinates.
  ///
  /// The highlights are painted here, above the searched subtree. The clips
  /// that hide the text (a scroll viewport, a `ClipRect`) do not apply to them
  /// unless we apply them ourselves. Returns null when nothing of the source
  /// shows, or when it is not below this layer at all.
  Rect? _visibleRegionOf(RenderObject source) {
    var region = Offset.zero & size;
    var child = source;
    while (!identical(child, this)) {
      final parent = child.parent;
      if (parent is! RenderObject) return null;
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        final mapped = MatrixUtils.transformRect(
          parent.getTransformTo(this),
          clip,
        );
        // A singular transform gives a rect that is not a number. Nothing
        // can be said to be visible through it.
        if (!mapped.isFinite) return null;
        region = region.intersect(mapped);
        if (region.isEmpty) return null;
      }
      child = parent;
    }
    return region;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);

    final sources = _controller.discoveredSources;
    if (sources.isEmpty) return;

    final canvas = context.canvas;
    final fill = Paint()..color = _color;
    final activeFill = Paint()..color = _activeColor;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    for (final source in sources) {
      if (source is! RenderedTextSource) continue;
      final matches = _controller.matchesFor(source);
      if (matches.isEmpty) continue;
      final visible = _visibleRegionOf(source.renderObject);
      if (visible == null) continue;
      for (final match in matches) {
        final active = _controller.isActive(match);
        for (final rect in source.boxesFor(match.start, match.end, this)) {
          // A zero-area box means the paragraph relaid out between the sweep
          // and this frame. Skip it instead of painting a sliver at the origin.
          // Empty is false for NaN. A box from a bad transform needs its own
          // check.
          if (!rect.isFinite || rect.isEmpty) continue;
          if (rect.intersect(visible).isEmpty) continue;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.inflate(1).intersect(visible),
              const Radius.circular(2),
            ),
            active ? activeFill : fill,
          );
        }
      }
    }
    canvas.restore();
  }
}
