import 'package:find_in_page/find_in_page.dart';
import 'package:find_in_page/src/highlight_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Find paints on top of the text; Flutter's selection paints behind it.
///
/// A page wrapped in `SelectionArea` is ordinary, and nobody had named
/// whether the two highlights collide or whether the overlay swallows a
/// drag. They do not: the overlay paints after the child and does not
/// hit-test, so both fills are in the display list and a mouse-drag still
/// selects. Same for `SelectableText`.
const _findFill = Color(0xAA112233);
const _findActive = Color(0xBB445566);
const _selectionFill = Color(0xCC778899);

const _haystack = 'needle in the needle stack';

/// Flutter 3.41.2: when `paints` replays an active selection on its mock
/// canvas, the framework creates `LeaderLayer`s for the selection handles that
/// leak tracking reports as not disposed: `_SelectableFragment.paint` under a
/// `SelectionArea` and `RenderEditable._paintHandleLayers` for a
/// `SelectableText`. Only the tests that select text ignore that one class;
/// drop this once the framework stops creating them there.
final _selectionPaintLeaks =
    LeakTesting.settings.withIgnored(classes: ['LeaderLayer']);

Offset _caretOf(RenderParagraph paragraph, int offset) {
  const caret = Rect.fromLTWH(0, 0, 2, 20);
  // getOffsetForCaret returns the top of the line. A drag that stays on
  // that edge misses the selectable inside a Scaffold; drop into the glyphs.
  return paragraph.localToGlobal(
    paragraph.getOffsetForCaret(TextPosition(offset: offset), caret) +
        const Offset(0, 8),
  );
}

RenderParagraph _paragraphOf(WidgetTester tester, String text) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
}

RenderHighlightOverlay _overlayOf(WidgetTester tester) {
  return tester.renderObject<RenderHighlightOverlay>(
    find.byType(HighlightOverlay),
  );
}

/// Whether [object] painted a [method] whose paint colour is [color].
///
/// `paints..rrect(color: ...)` matches the *next* `drawRRect`, so a
/// Material rrect painted first, or the inactive fill painted before the
/// active one, fails a check that only cares that the colour is there.
PaintPattern _painted(Symbol method, Color color) {
  return paints
    ..something((name, args) {
      if (name != method || args.isEmpty || args.last is! Paint) {
        return false;
      }
      final painted = (args.last as Paint).color;
      const limit = 1 / 255;
      return (painted.a - color.a).abs() < limit &&
          (painted.r - color.r).abs() < limit &&
          (painted.g - color.g).abs() < limit &&
          (painted.b - color.b).abs() < limit;
    });
}

void _expectFindHighlights(RenderObject overlay) {
  expect(overlay, _painted(#drawRRect, _findActive));
  expect(overlay, _painted(#drawRRect, _findFill));
}

Future<void> _openFindBar(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Mouse-drag selection, the path Flutter's own SelectionArea tests use.
Future<void> _dragSelect(
  WidgetTester tester, {
  required Offset from,
  required Offset to,
}) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(to);
  await gesture.up();
  await tester.pump();
}

Widget _selectionInsideScope({
  required FindInPageController controller,
  required Widget body,
  ValueChanged<SelectedContent?>? onSelectionChanged,
}) {
  return MaterialApp(
    home: FindInPageScope(
      controller: controller,
      highlightColor: _findFill,
      activeHighlightColor: _findActive,
      child: SelectionArea(
        onSelectionChanged: onSelectionChanged,
        child: body,
      ),
    ),
  );
}

Widget _scopeInsideSelection({
  required FindInPageController controller,
  required Widget body,
  ValueChanged<SelectedContent?>? onSelectionChanged,
}) {
  return MaterialApp(
    home: SelectionArea(
      onSelectionChanged: onSelectionChanged,
      child: FindInPageScope(
        controller: controller,
        highlightColor: _findFill,
        activeHighlightColor: _findActive,
        child: body,
      ),
    ),
  );
}

Widget _body() => const Scaffold(
      body: Center(
        child: Text(_haystack, selectionColor: _selectionFill),
      ),
    );

void main() {
  group('SelectionArea', () {
    testWidgets('finds and highlights text the area made selectable',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _selectionInsideScope(controller: controller, body: _body()),
      );
      await _openFindBar(tester);
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump();

      expect(controller.matchCount, 2);
      expect(find.byType(FindBar), findsOneWidget);
      _expectFindHighlights(_overlayOf(tester));
    });

    testWidgets(
        'selecting while the bar is open paints both highlights and '
        'does not swallow either side\'s gestures', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      SelectedContent? selected;

      await tester.pumpWidget(
        _selectionInsideScope(
          controller: controller,
          onSelectionChanged: (value) => selected = value,
          body: _body(),
        ),
      );
      await _openFindBar(tester);
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump();
      expect(controller.matchCount, 2);
      expect(controller.activeMatchIndex, 0);

      final paragraph = _paragraphOf(tester, _haystack);
      await _dragSelect(
        tester,
        from: _caretOf(paragraph, 0),
        to: _caretOf(paragraph, 6),
      );

      expect(paragraph.selections, isNotEmpty);
      expect(paragraph.selections.single.isCollapsed, isFalse);
      expect(selected?.plainText, isNotEmpty);
      expect(paragraph, _painted(#drawRect, _selectionFill));
      _expectFindHighlights(_overlayOf(tester));
      expect(controller.matchCount, 2);
      expect(controller.activeMatchIndex, 0);
      expect(find.byType(FindBar), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(controller.activeMatchIndex, 1);
      _expectFindHighlights(_overlayOf(tester));
    }, experimentalLeakTesting: _selectionPaintLeaks);

    testWidgets(
        'a SelectionArea outside the scope, the other ordinary wrapping, '
        'behaves the same', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      SelectedContent? selected;

      await tester.pumpWidget(
        _scopeInsideSelection(
          controller: controller,
          onSelectionChanged: (value) => selected = value,
          body: _body(),
        ),
      );
      await _openFindBar(tester);
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump();
      expect(controller.matchCount, 2);
      _expectFindHighlights(_overlayOf(tester));

      final paragraph = _paragraphOf(tester, _haystack);
      await _dragSelect(
        tester,
        from: _caretOf(paragraph, 0),
        to: _caretOf(paragraph, 6),
      );
      expect(paragraph.selections, isNotEmpty);
      expect(paragraph.selections.single.isCollapsed, isFalse);
      expect(selected?.plainText, isNotEmpty);
      expect(paragraph, _painted(#drawRect, _selectionFill));
      _expectFindHighlights(_overlayOf(tester));

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(controller.activeMatchIndex, 1);
    }, experimentalLeakTesting: _selectionPaintLeaks);
  });

  group('SelectableText', () {
    testWidgets(
        'selecting while the bar is open paints both highlights and '
        'does not swallow either side\'s gestures', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      TextSelection? selection;

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            highlightColor: _findFill,
            activeHighlightColor: _findActive,
            child: Scaffold(
              body: Center(
                child: SelectableText(
                  _haystack,
                  style: const TextStyle(fontSize: 24),
                  selectionColor: _selectionFill,
                  onSelectionChanged: (value, _) => selection = value,
                ),
              ),
            ),
          ),
        ),
      );
      await _openFindBar(tester);
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pump();

      expect(controller.matchCount, 2);
      expect(controller.discoveredSources, hasLength(1));
      expect(
        controller.discoveredSources.single,
        isA<ReadOnlyEditableSource>(),
      );
      _expectFindHighlights(_overlayOf(tester));

      final editable =
          (controller.discoveredSources.single as ReadOnlyEditableSource)
              .editable;
      final boxes = editable.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      expect(boxes, isNotEmpty);
      final from = editable.localToGlobal(boxes.first.toRect().centerLeft);
      final to = editable.localToGlobal(boxes.first.toRect().centerRight);
      await _dragSelect(tester, from: from, to: to);

      expect(selection, isNotNull);
      expect(selection!.isCollapsed, isFalse);
      expect(editable, _painted(#drawRect, _selectionFill));
      _expectFindHighlights(_overlayOf(tester));
      expect(controller.matchCount, 2);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(controller.activeMatchIndex, 1);
      _expectFindHighlights(_overlayOf(tester));
    }, experimentalLeakTesting: _selectionPaintLeaks);
  });
}
