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
List<RenderedTextSource> discoverTextSources(
  RenderObject root, {
  Iterable<RenderedTextSource> previous = const [],
}) {
  final reuse = <RenderObject, RenderedTextSource>{
    for (final source in previous) source.renderObject: source,
  };
  final found = <RenderedTextSource>[];

  void add(RenderBox node, RenderedTextSource Function() create) {
    if (!node.hasSize) return;
    final source = reuse[node] ?? create();
    if (!_hasReadableText(source.findableText)) return;
    found.add(source);
  }

  void visit(RenderObject node) {
    // A widget that reports its own text owns its whole subtree, and so does
    // anything the app asked to keep out of find. Descending would count those
    // matches twice, or count text the reader did not ask about.
    if (node is RenderExcludeFromFind) return;
    switch (node) {
      case final RenderParagraph paragraph:
        add(paragraph, () => ParagraphSource(paragraph));
      case final RenderEditable editable
          when editable.readOnly && !editable.obscureText:
        add(editable, () => ReadOnlyEditableSource(editable));
      default:
        break;
    }
    node.visitChildren(visit);
  }

  visit(root);
  return found;
}
