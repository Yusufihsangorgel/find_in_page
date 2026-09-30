import 'dart:collection';

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
  /// visible.
  void showMatchOnScreen(int start, int end) {
    final box = renderObject;
    if (!box.attached || !box.hasSize) return;
    final boxes = textBoxes(start, end);
    box.showOnScreen(
      descendant: box,
      rect: boxes.isEmpty ? null : boxes.first.toRect(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RenderedTextSource &&
      identical(other.renderObject, renderObject);

  @override
  int get hashCode => identityHashCode(renderObject);
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
    final private = (rune >= 0xE000 && rune <= 0xF8FF) ||
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
  final byTop = <int>[
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
