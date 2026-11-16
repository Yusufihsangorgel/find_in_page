import 'package:find_in_page/find_in_page.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Navigating inside one paragraph that is taller than its viewport.
///
/// Scrolling the whole paragraph into view is not enough here: any fixed
/// position for the paragraph shows only a band of its lines. The matches sit
/// near the top, the middle and the bottom, and every step checks that the
/// active one is on screen.
void main() {
  _testTallParagraph(
    'Text',
    (data, key) => Text(data, key: key),
    (tester, key) => tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
    ),
  );
  _testTallParagraph(
    'SelectableText',
    (data, key) => SelectableText(data, key: key),
    (tester, key) => tester
        .state<EditableTextState>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable,
  );
  _testTallParagraph(
    'FindableText',
    (data, key) => FindableText(data, key: key),
    (tester, key) => tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
    ),
  );
}

void _testTallParagraph(
  String widgetName,
  Widget Function(String data, Key key) buildText,
  RenderBox Function(WidgetTester tester, Key key) findText,
) {
  testWidgets('shows each matched line of a tall $widgetName', (tester) async {
    final controller = FindInPageController();
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    const viewportKey = ValueKey('viewport');
    const textKey = ValueKey('paragraph');
    const needleLines = {5, 40, 75};
    final data = [
      for (var line = 1; line <= 80; line++)
        needleLines.contains(line) ? 'line $line needle' : 'line $line',
    ].join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: FindInPageScope(
          controller: controller,
          child: Scaffold(
            body: SizedBox(
              width: 320,
              height: 220,
              child: SingleChildScrollView(
                key: viewportKey,
                controller: scrollController,
                child: buildText(data, textKey),
              ),
            ),
          ),
        ),
      ),
    );

    final viewport = tester.renderObject<RenderBox>(find.byKey(viewportKey));
    expect(
      tester.getSize(find.byKey(textKey)).height,
      greaterThan(viewport.size.height * 4),
      reason: 'the paragraph has to be much taller than its viewport',
    );

    void expectActiveMatchOnScreen(String step) {
      final match = controller.activeMatch!;
      final text = findText(tester, textKey);
      final selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
      final boxes = switch (text) {
        final RenderParagraph p => p.getBoxesForSelection(selection),
        final RenderEditable e => e.getBoxesForSelection(selection),
        _ => throw StateError('no text render object for $widgetName'),
      };
      expect(boxes, isNotEmpty, reason: step);
      final rect = MatrixUtils.transformRect(
        text.getTransformTo(viewport),
        boxes.first.toRect(),
      );
      // Scrolling down puts the match against the bottom edge, and
      // Rect.contains leaves that edge out. Compare the edges instead.
      expect(rect.top, greaterThanOrEqualTo(-0.5), reason: step);
      expect(
        rect.bottom,
        lessThanOrEqualTo(viewport.size.height + 0.5),
        reason: step,
      );
    }

    controller.search('needle');
    await tester.pumpAndSettle();
    expect(controller.matchCount, 3);
    expectActiveMatchOnScreen('first match, line 5');
    expect(
      scrollController.offset,
      0,
      reason: 'a match that is already on screen should not move the page',
    );

    controller.next();
    await tester.pumpAndSettle();
    expectActiveMatchOnScreen('next, line 40');

    controller.next();
    await tester.pumpAndSettle();
    expectActiveMatchOnScreen('next, line 75');

    controller.next();
    await tester.pumpAndSettle();
    expectActiveMatchOnScreen('next wraps to line 5');

    controller.previous();
    await tester.pumpAndSettle();
    expectActiveMatchOnScreen('previous wraps to line 75');
  });
}
