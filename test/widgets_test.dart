import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Collects the text of highlighted (background-colored) spans in every
/// rendered rich text.
List<String> _highlightedSegments(WidgetTester tester) {
  final segments = <String>[];
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      if (span is TextSpan &&
          span.style?.backgroundColor != null &&
          span.text != null) {
        segments.add(span.text!);
      }
      return true;
    });
  }
  return segments;
}

void main() {
  group('FindableText', () {
    testWidgets('registers with the scope and highlights matches',
        (tester) async {
      final controller = FindInPageController();
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const Column(
            children: [
              FindableText('The cat sat on the mat.'),
              FindableText('Another cat.'),
            ],
          ),
        ),
      ));

      controller.search('cat');
      await tester.pump();

      expect(controller.matchCount, 2);
      expect(_highlightedSegments(tester), ['cat', 'cat']);
    });

    testWidgets('active match uses the active highlight color', (tester) async {
      final controller = FindInPageController();
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('a b a'),
        ),
      ));
      controller.search('a');
      await tester.pump();

      Color? colorOfSegment(int index) {
        final colors = <Color?>[];
        for (final richText
            in tester.widgetList<RichText>(find.byType(RichText))) {
          richText.text.visitChildren((span) {
            if (span is TextSpan && span.style?.backgroundColor != null) {
              colors.add(span.style!.backgroundColor);
            }
            return true;
          });
        }
        return colors[index];
      }

      final firstActive = colorOfSegment(0);
      controller.next();
      await tester.pump();
      final firstAfterNext = colorOfSegment(0);
      expect(firstActive, isNot(equals(firstAfterNext)));
    });

    testWidgets('unregisters on dispose', (tester) async {
      final controller = FindInPageController();
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const Column(
            children: [FindableText('alpha'), FindableText('alpha beta')],
          ),
        ),
      ));
      controller.search('alpha');
      await tester.pump();
      expect(controller.matchCount, 2);

      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const Column(children: [FindableText('alpha')]),
        ),
      ));
      await tester.pump();
      expect(controller.matchCount, 1);
    });

    testWidgets('updates matches when its text changes', (tester) async {
      final controller = FindInPageController();
      Widget build(String text) => _app(
            FindInPageScope(
              controller: controller,
              child: FindableText(text),
            ),
          );
      await tester.pumpWidget(build('one match'));
      controller.search('match');
      await tester.pump();
      expect(controller.matchCount, 1);

      await tester.pumpWidget(build('match and match'));
      await tester.pump();
      expect(controller.matchCount, 2);
    });

    testWidgets('renders plain text without a scope', (tester) async {
      await tester.pumpWidget(_app(const FindableText('standalone')));
      expect(find.text('standalone'), findsOneWidget);
    });

    testWidgets('scrolls the active match into view', (tester) async {
      final controller = FindInPageController();
      final scrollController = ScrollController();
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: [
                const SizedBox(height: 2000),
                const FindableText('needle far below the fold'),
              ],
            ),
          ),
        ),
      ));

      expect(scrollController.offset, 0);
      controller.search('needle');
      await tester.pumpAndSettle();
      expect(scrollController.offset, greaterThan(0));
    });
  });

  group('FindBar and scope shortcuts', () {
    testWidgets('Ctrl+F opens the bar, Escape closes it and clears',
        (tester) async {
      final controller = FindInPageController();
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('searchable content'),
        ),
      ));
      expect(find.byType(FindBar), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byType(FindBar), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'content');
      await tester.pump();
      expect(controller.matchCount, 1);
      expect(find.text('1/1'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(FindBar), findsNothing);
      expect(controller.query, isEmpty);
    });

    testWidgets('bar is visible and tappable with a shrink-wrapped child',
        (tester) async {
      // Regression: with the old Stack overlay, a small child collapsed the
      // bar to zero size, making it invisible and untappable.
      final controller = FindInPageController();
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: const FindableText('go go go'),
        ),
      ));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final barSize = tester.getSize(find.byType(FindBar));
      expect(barSize.height, greaterThan(30));
      expect(barSize.width, greaterThan(150));

      await tester.enterText(find.byType(TextField), 'go');
      await tester.pump();
      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(controller.activeMatchIndex, 1);
    });

    testWidgets('shrinking a searched text does not crash', (tester) async {
      // Regression: stale match offsets caused a substring RangeError on
      // the frame between a text change and the deferred recompute.
      final controller = FindInPageController();
      Widget build(String text) => _app(
            FindInPageScope(
              controller: controller,
              child: FindableText(text),
            ),
          );
      await tester.pumpWidget(build('match and match'));
      controller.search('match');
      await tester.pump();
      expect(controller.matchCount, 2);

      await tester.pumpWidget(build('no'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.matchCount, 0);
    });

    testWidgets(
        'showBar: false routes the shortcut to onOpenRequested and '
        'Escape does not clear the search', (tester) async {
      final controller = FindInPageController();
      var opened = 0;
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          showBar: false,
          onOpenRequested: () => opened++,
          child: const FindableText('needle'),
        ),
      ));
      controller.search('needle');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(opened, 1);
      expect(find.byType(FindBar), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.query, 'needle');
    });

    testWidgets('does not steal a user autofocus', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(_app(
        FindInPageScope(
          child: Column(
            children: [
              TextField(focusNode: focusNode, autofocus: true),
              const FindableText('content'),
            ],
          ),
        ),
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('bar fits a 360dp viewport without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = FindInPageController();
      await tester.pumpWidget(_app(
        FindInPageScope(
          controller: controller,
          child: ListView(children: const [FindableText('word word')]),
        ),
      ));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'word');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('field reflects programmatic search when unfocused',
        (tester) async {
      final controller = FindInPageController();
      await tester.pumpWidget(_app(
        Column(
          children: [
            FindBar(controller: controller, autofocus: false),
            FindableText('alpha beta', controller: controller),
          ],
        ),
      ));
      controller.search('alpha');
      await tester.pump();
      expect(find.widgetWithText(TextField, 'alpha'), findsOneWidget);
    });

    testWidgets('bar buttons navigate and close', (tester) async {
      final controller = FindInPageController();
      var closed = false;
      await tester.pumpWidget(_app(
        Column(
          children: [
            FindBar(controller: controller, onClose: () => closed = true),
            FindableText('go go go', controller: controller),
          ],
        ),
      ));

      await tester.enterText(find.byType(TextField), 'go');
      await tester.pump();
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous match'));
      await tester.pump();
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      expect(closed, isTrue);
    });
  });
}
