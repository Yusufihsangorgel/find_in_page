import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _testTallParagraphReveal(
    'Text',
    (data, key) => Text(data, key: key),
    (tester, key) => tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byKey(key),
            matching: find.byType(RichText),
          )
          .first,
    ),
  );
  _testTallParagraphReveal(
    'SelectableText',
    (data, key) => SelectableText(data, key: key),
    (tester, key) => tester
        .state<EditableTextState>(
          find
              .descendant(
                of: find.byKey(key),
                matching: find.byType(EditableText),
              )
              .first,
        )
        .renderEditable,
  );
  _testTallParagraphReveal(
    'FindableText',
    (data, key) => FindableText(data, key: key),
    (tester, key) => tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byKey(key),
            matching: find.byType(RichText),
          )
          .first,
    ),
  );
}

void _testTallParagraphReveal(
  String widgetName,
  Widget Function(String data, Key key) buildText,
  RenderBox Function(WidgetTester tester, Key key) findTextRenderObject,
) {
  testWidgets(
    'reveals the matched line inside a tall paragraph for $widgetName',
    (tester) async {
      final controller = FindInPageController();
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      final viewportKey = ValueKey('$widgetName viewport');
      final textKey = ValueKey('$widgetName paragraph');
      final data = List.generate(
        80,
        (index) => index == 69
            ? 'line ${index + 1} needle'
            : 'line ${index + 1} content',
      ).join('\n');

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

      controller.search('needle');
      await tester.pumpAndSettle();

      final match = controller.activeMatch!;
      final paragraph = findTextRenderObject(tester, textKey);
      final viewport = tester.renderObject<RenderBox>(find.byKey(viewportKey));
      final selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
      final List<TextBox> boxes;
      if (paragraph is RenderParagraph) {
        boxes = paragraph.getBoxesForSelection(selection);
      } else if (paragraph is RenderEditable) {
        boxes = paragraph.getBoxesForSelection(selection);
      } else {
        throw StateError('The text widget has no supported render object');
      }
      expect(boxes, isNotEmpty);

      final matchRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(viewport),
        boxes.first.toRect(),
      );
      // Scrolling down aligns the match with the bottom edge, and
      // Rect.contains excludes that edge; compare the edges directly.
      expect(matchRect.top, greaterThanOrEqualTo(-0.5));
      expect(matchRect.bottom, lessThanOrEqualTo(viewport.size.height + 0.5));
    },
  );
}
