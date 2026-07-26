import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'auto_discovery.dart';
import 'controller.dart';

/// Paints match highlights over text the application never wrapped.
///
/// `FindableText` highlights by restyling its own spans, which is sharper and
/// composes with the text's own decoration. That is not available for text
/// belonging to widgets we do not own, so those matches are drawn on top
/// instead, the way a browser draws its own find highlights.
///
/// Sits directly above the searched subtree, so the rectangles it paints are
/// clipped by the same scroll viewports that clip the text.
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
      for (final match in _controller.matchesFor(source)) {
        final active = _controller.isActive(match);
        for (final rect in source.boxesFor(match.start, match.end, this)) {
          // A zero-area box means the paragraph relaid out between the sweep
          // and this frame; skip rather than paint a sliver at the origin.
          if (rect.isEmpty) continue;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.inflate(1),
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
