import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'exclude_from_find.dart';

/// A [FindableSource] for text the application never wrapped.
///
/// Every string Flutter draws ends up in a render object that knows how to
/// report the rectangles covering a range of its characters. Reading those
/// directly is what lets find-in-page work on a page with no changes to it,
/// instead of requiring every string to be wrapped by hand.
///
/// The render object is the identity: the same one always yields an equal
/// source, so matches survive a recompute and the controller's registration
/// bookkeeping stays stable across frames.
sealed class RenderedTextSource implements FindableSource {
  const RenderedTextSource();

  /// The render object this source reads.
  RenderBox get renderObject;

  /// Always null.
  ///
  /// There is no element to hand to `Scrollable.ensureVisible`, because the
  /// widget that built this text is not ours. Revealing goes through
  /// [showMatchOnScreen] instead, which asks the render object directly and can
  /// aim at the matched characters rather than at the whole block.
  @override
  BuildContext? get findableContext => null;

  /// The boxes covering [start]..[end], in the render object's own space.
  List<TextBox> textBoxes(int start, int end);

  /// The rectangles covering [start]..[end], in the coordinate space of
  /// [ancestor].
  ///
  /// A match can span more than one rectangle when it wraps across lines.
  /// Returns an empty list when the render object has been detached or has not
  /// been laid out yet, which happens routinely while a list is scrolling.
  List<Rect> boxesFor(int start, int end, RenderObject ancestor) {
    final box = renderObject;
    if (!box.attached || !box.hasSize) return const [];
    final transform = box.getTransformTo(ancestor);
    return [
      for (final textBox in textBoxes(start, end))
        MatrixUtils.transformRect(transform, textBox.toRect()),
    ];
  }

  /// Scrolls whatever viewports contain this text until [start]..[end] is
  /// visible, with a margin above and below it.
  ///
  /// This method does not know where a find bar is. It keeps 72 logical
  /// pixels at both edges, or a quarter of the shortest enclosing vertical
  /// viewport when that is less. A match already at least that far from both
  /// edges stays where it is. Near the start or end of the scroll range the
  /// margin shrinks to what the range allows. The controller reveals the
  /// active match with the scope's bar taken into account.
  void showMatchOnScreen(int start, int end) {
    showTextOnScreen(this, start, end);
  }

  @override
  bool operator ==(Object other) =>
      other is RenderedTextSource &&
      identical(other.renderObject, renderObject);

  @override
  int get hashCode => identityHashCode(renderObject);
}

/// The gap kept between a revealed match and the bar, and between the match
/// and a viewport edge with no bar over it, in logical pixels.
const double _barGap = 16;

/// The gap kept at both edges when no bar is known, in logical pixels.
///
/// A scope with `showBar: false` leaves the find UI to the app, and a direct
/// call to [RenderedTextSource.showMatchOnScreen] has no bar at all. Either
/// way the bar could be anywhere. 72 clears the built-in bar at a text scale
/// of 1, 56 tall and 8 below the top of the safe area.
const double _revealMargin = 72;

/// How long a reveal animates.
const Duration _revealDuration = Duration(milliseconds: 200);

/// Scrolls the viewports around [source] until [start]..[end] is visible with
/// a margin above and below it.
///
/// [bar] is where the find bar is on screen, in global coordinates, or null
/// when there is none to measure. The returned [match] is the first box of the
/// range and [shown] is that box with its margin, both in the coordinates of
/// the source's render object. Returns null when the render object is not laid
/// out, or when the range has no box and the whole text was revealed instead.
({Rect match, Rect shown})? showTextOnScreen(
  RenderedTextSource source,
  int start,
  int end, {
  Rect? bar,
}) {
  final box = source.renderObject;
  if (!box.attached || !box.hasSize) return null;
  final boxes = source.textBoxes(start, end);
  if (boxes.isEmpty) {
    box.showOnScreen(
      descendant: box,
      duration: _revealDuration,
      curve: Curves.easeInOut,
    );
    return null;
  }
  final match = boxes.first.toRect();
  final shown = _withRevealMargin(box, match, bar);
  box.showOnScreen(
    descendant: box,
    rect: shown,
    duration: _revealDuration,
    curve: Curves.easeInOut,
  );
  return (match: match, shown: shown);
}

/// [match] with the reveal margin added above and below.
///
/// With [bar] known, the margin at the edge the bar covers is the depth of
/// the bar inside the outermost vertical viewport around [box], plus
/// [_barGap]. That viewport is the one fixed on screen, and its edge is where
/// a match lands when it has to scroll. The other edge gets [_barGap]. The
/// bar grows with the text scale and can take a second row, and the margin
/// follows. Without [bar] both edges get [_revealMargin].
///
/// The two margins together take at most half of the shortest vertical
/// viewport around [box], shared in proportion. In a short scroll view that
/// leaves the other half for the match and for matches that need no
/// scrolling. Only the vertical extent grows: the find bar spans the top of
/// the screen, and a horizontal margin would only make a sideways list scroll
/// further than needed.
Rect _withRevealMargin(RenderObject box, Rect match, Rect? bar) {
  RenderBox? outermost;
  var shortest = double.infinity;
  for (var node = box.parent; node != null; node = node.parent) {
    if (node is RenderBox &&
        node is RenderAbstractViewport &&
        node.hasSize &&
        _scrollsVertically(node as RenderAbstractViewport, box, match)) {
      outermost = node;
      shortest = math.min(shortest, node.size.height);
    }
  }
  var above = bar == null ? _revealMargin : _barGap;
  var below = above;
  if (bar != null && outermost != null) {
    final viewport = MatrixUtils.transformRect(
      outermost.getTransformTo(null),
      Offset.zero & outermost.size,
    );
    if (bar.left < viewport.right && bar.right > viewport.left) {
      if (bar.center.dy < viewport.center.dy) {
        above += math.max(0, bar.bottom - viewport.top);
      } else {
        below += math.max(0, viewport.bottom - bar.top);
      }
    }
  }
  final room = shortest / 2;
  if (above + below > room) {
    final share = room / (above + below);
    above *= share;
    below *= share;
  }
  return Rect.fromLTRB(
    match.left,
    match.top - above,
    match.right,
    match.bottom + below,
  );
}

/// Whether [viewport] scrolls [box] up and down.
///
/// Moving [match] down a pixel changes the offset that reveals it only in a
/// viewport that scrolls vertically. A sideways one, such as a row of chips
/// 48 tall, says nothing about the room above and below the match, and its
/// height would cut the margin to 12.
bool _scrollsVertically(
  RenderAbstractViewport viewport,
  RenderObject box,
  Rect match,
) {
  double offsetFor(Rect rect) => viewport
      .getOffsetToReveal(box, 0, rect: rect, axis: Axis.vertical)
      .offset;
  return offsetFor(match) != offsetFor(match.translate(0, 1));
}

/// Text drawn by a `Text`, `Text.rich`, or any widget that builds one,
/// including titles supplied to widgets you do not own such as `AppBar`,
/// `ListTile` and `DataTable`.
final class ParagraphSource extends RenderedTextSource {
  /// Reads [paragraph].
  const ParagraphSource(this.paragraph);

  /// The paragraph this source reads.
  final RenderParagraph paragraph;

  @override
  RenderBox get renderObject => paragraph;

  @override
  String get findableText =>
      paragraph.attached ? paragraph.text.toPlainText() : '';

  @override
  List<TextBox> textBoxes(int start, int end) => paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
}

/// Text drawn by a read-only editable, which in practice means
/// `SelectableText`.
///
/// Editable fields are deliberately excluded. A browser's find bar does not
/// match inside `<input>` values either: an editable field is a control the
/// user is filling in, not content on the page. The read-only flag is exactly
/// the line Flutter itself draws, since `SelectableText` builds its editable
/// with `readOnly: true`.
final class ReadOnlyEditableSource extends RenderedTextSource {
  /// Reads [editable].
  const ReadOnlyEditableSource(this.editable);

  /// The editable this source reads.
  final RenderEditable editable;

  @override
  RenderBox get renderObject => editable;

  @override
  String get findableText =>
      editable.attached ? (editable.text?.toPlainText() ?? '') : '';

  @override
  List<TextBox> textBoxes(int start, int end) => editable.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
}

/// Whether [text] contains anything a person would search for.
///
/// Flutter draws an `Icon` as a glyph inside a paragraph like any other text,
/// so a naive sweep picks up every chevron and close button as a searchable
/// one-character string. Those glyphs live in the Unicode Private Use Area, and
/// a `WidgetSpan` leaves the object replacement character behind, so a string
/// made only of those is decoration rather than content.
bool _hasReadableText(String text) {
  for (final rune in text.runes) {
    final private =
        (rune >= 0xE000 && rune <= 0xF8FF) ||
        (rune >= 0xF0000 && rune <= 0xFFFFD) ||
        (rune >= 0x100000 && rune <= 0x10FFFD);
    if (private || rune == 0xFFFC) continue;
    if (rune == 0x20 || rune == 0x0A || rune == 0x09 || rune == 0x0D) continue;
    return true;
  }
  return false;
}

/// Orders [children] from the top of the page to the bottom.
///
/// Children that overlap vertically form a group and keep their child-list
/// order inside it. That covers a label beside a taller value and an overlay
/// stacked on content, which are visited in the order the widgets were built.
/// Groups follow each other by top edge. A `Scaffold` builds its body before
/// its app bar because the bar paints on top. This puts the bar back in front
/// of the body.
///
/// A `Scaffold` lays out `drawer` and `endDrawer` over the whole screen even
/// while they are closed. Their boxes overlap the app bar and the body, and
/// would join the two into one group in build order. Children of a custom
/// multi-child layout with a drawer slot id are set aside instead. They are
/// visited last, in child-list order. A body that extends behind the app
/// bar with `extendBodyBehindAppBar` still overlaps it and keeps build order.
///
/// The child list is returned unchanged unless every child is an attached
/// [RenderBox] with a finite size and position. That leaves slivers, viewports
/// and children that have not been laid out in child-list order. It is also
/// returned unchanged if a transform cannot be computed for a child.
List<RenderObject> _inVisualOrder(
  RenderObject parent,
  List<RenderObject> children,
) {
  if (children.length < 2) return children;
  final bounds = <Rect>[];
  for (final child in children) {
    if (child is! RenderBox || !child.attached || !child.hasSize) {
      return children;
    }
    final Rect rect;
    try {
      rect = MatrixUtils.transformRect(
        child.getTransformTo(null),
        Offset.zero & child.size,
      );
    } catch (_) {
      // An unusual sliver ancestor can refuse to report a transform. Losing the
      // ordering for this node is better than losing the whole search.
      return children;
    }
    if (!rect.isFinite) return children;
    bounds.add(rect);
  }
  final backdrops = <int>{};
  if (parent is RenderCustomMultiChildLayoutBox) {
    for (var i = 0; i < children.length; i++) {
      final data = children[i].parentData;
      if (data is MultiChildLayoutParentData &&
          data.id.toString().toLowerCase().endsWith('drawer')) {
        backdrops.add(i);
      }
    }
  }
  final byTop =
      <int>[
        for (var i = 0; i < children.length; i++)
          if (!backdrops.contains(i)) i,
      ]..sort((a, b) {
        final top = bounds[a].top.compareTo(bounds[b].top);
        return top != 0 ? top : a.compareTo(b);
      });
  final ordered = <RenderObject>[];
  final group = <int>[];
  var groupBottom = double.negativeInfinity;
  void flush() {
    group.sort();
    for (final index in group) {
      ordered.add(children[index]);
    }
    group.clear();
  }

  for (final index in byTop) {
    if (group.isNotEmpty && bounds[index].top >= groupBottom) {
      flush();
      groupBottom = double.negativeInfinity;
    }
    group.add(index);
    if (bounds[index].bottom > groupBottom) groupBottom = bounds[index].bottom;
  }
  flush();
  for (final index in backdrops.toList()..sort()) {
    ordered.add(children[index]);
  }
  return ordered;
}

/// A sweep's text and the positions used to order all sources.
///
/// This remains a list so callers that only need discovered text can use it
/// as before. [positions] numbers render objects in the order the sweep
/// visited them, which is top to bottom where children are laid out as boxes.
/// It also includes nodes inside excluded subtrees, where registered sources
/// may have their anchors.
final class DiscoveredTextSources extends ListBase<RenderedTextSource> {
  DiscoveredTextSources(this._sources, this.positions);

  final List<RenderedTextSource> _sources;
  final Map<RenderObject, int> positions;

  @override
  int get length => _sources.length;

  @override
  set length(int value) => throw UnsupportedError('Cannot change a sweep');

  @override
  RenderedTextSource operator [](int index) => _sources[index];

  @override
  void operator []=(int index, RenderedTextSource value) =>
      throw UnsupportedError('Cannot change a sweep');
}

/// Finds the text currently rendered under [root].
///
/// Reuses the source already held for a render object so that repeated sweeps
/// return equal objects; [previous] is the result of the last sweep.
///
/// Only laid-out render objects holding non-empty text are returned. Obscured
/// and editable fields are skipped, and so is anything under an
/// [ExcludeFromFind], which is how a widget keeps ownership of its own text.
/// Text that has scrolled out of a lazy list is not here at all, because it
/// does not exist yet; `FindableListView` covers that case and the two compose.
DiscoveredTextSources discoverTextSources(
  RenderObject root, {
  Iterable<RenderedTextSource> previous = const [],
}) {
  final reuse = <RenderObject, RenderedTextSource>{
    for (final source in previous) source.renderObject: source,
  };
  final found = <RenderedTextSource>[];
  final positions = <RenderObject, int>{};

  void add(RenderBox node, RenderedTextSource Function() create) {
    if (!node.hasSize) return;
    final source = reuse[node] ?? create();
    if (!_hasReadableText(source.findableText)) return;
    found.add(source);
  }

  void visit(RenderObject node, bool excluded) {
    positions[node] = positions.length;
    // Excluded text still has a place in the page. Walk through it so an
    // explicitly registered source can use its render object as an anchor.
    final skipText = excluded || node is RenderExcludeFromFind;
    if (!skipText) {
      switch (node) {
        case final RenderParagraph paragraph:
          add(paragraph, () => ParagraphSource(paragraph));
        case final RenderEditable editable
            when editable.readOnly && !editable.obscureText:
          add(editable, () => ReadOnlyEditableSource(editable));
        default:
          break;
      }
    }
    final children = <RenderObject>[];
    node.visitChildren(children.add);
    for (final child in _inVisualOrder(node, children)) {
      visit(child, skipText);
    }
  }

  visit(root, false);
  return DiscoveredTextSources(found, positions);
}
