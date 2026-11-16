import 'package:find_in_page/find_in_page.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a revealed match lands: clear of the find bar at any text scale,
/// inside small and nested scroll views, and not moved when it is already well
/// on screen.
///
/// Every case runs for `FindableText` and for a plain `Text` found by
/// discovery. Both go through the same reveal.
void main() {
  for (final kind in _Kind.values) {
    group(kind.name, () {
      // The built-in bar grows with the text scale and takes a second row on
      // a phone from 1.5 up. Its lower edge moves from 64 to 112, past any
      // fixed margin that suits a scale of 1.
      for (final scale in [1.0, 1.5, 2.0, 3.0]) {
        testWidgets('stays clear of the bar at text scale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(400, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final controller = FindInPageController();
          final scroll = ScrollController();
          addTearDown(controller.dispose);
          addTearDown(scroll.dispose);

          await tester.pumpWidget(
            _page(kind, controller: controller, scroll: scroll),
          );
          controller.open();
          await tester.pumpAndSettle();
          final bar = tester.getRect(find.byType(FindBar));
          final body = tester.getRect(find.byType(SingleChildScrollView));
          expect(bar.top, lessThan(body.top + 60), reason: 'bar $bar');

          Future<void> step(void Function() move, String name) async {
            final before = scroll.offset;
            move();
            await tester.pumpAndSettle();
            final rect = _activeRect(tester, controller);
            expect(_inside(rect, body), isTrue, reason: '$name: $rect');
            expect(
              rect.overlaps(bar),
              isFalse,
              reason: '$name: $rect under the bar $bar',
            );
            // Every step scrolls. Going up, the match stops 16 below the bar.
            // Going down, 16 above the bottom edge.
            expect(scroll.offset, isNot(before), reason: name);
            if (scroll.offset < before) {
              expect(rect.top - bar.bottom, closeTo(16, 0.5), reason: name);
            } else {
              expect(body.bottom - rect.bottom, closeTo(16, 0.5), reason: name);
            }
          }

          await step(() => controller.search('needle'), 'search, line 60');
          await step(controller.next, 'next, line 120');
          await step(controller.next, 'next, line 190');
          await step(controller.next, 'next scrolls up to line 60');
          await step(controller.previous, 'previous scrolls down to line 190');
          await step(controller.previous, 'previous scrolls up to line 120');
        });
      }

      testWidgets('stays clear of a bar at the bottom', (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = FindInPageController();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);

        await tester.pumpWidget(
          _page(
            kind,
            controller: controller,
            scroll: scroll,
            barAlignment: Alignment.bottomCenter,
          ),
        );
        controller.open();
        await tester.pumpAndSettle();
        final bar = tester.getRect(find.byType(FindBar));
        final body = tester.getRect(find.byType(SingleChildScrollView));
        expect(bar.bottom, greaterThan(body.bottom - 60), reason: 'bar $bar');

        Future<void> step(void Function() move, String name) async {
          final before = scroll.offset;
          move();
          await tester.pumpAndSettle();
          final rect = _activeRect(tester, controller);
          expect(_inside(rect, body), isTrue, reason: '$name: $rect');
          expect(rect.overlaps(bar), isFalse, reason: '$name: $rect $bar');
          expect(scroll.offset, isNot(before), reason: name);
          if (scroll.offset > before) {
            expect(bar.top - rect.bottom, closeTo(16, 0.5), reason: name);
          } else {
            expect(rect.top - body.top, closeTo(16, 0.5), reason: name);
          }
        }

        await step(() => controller.search('needle'), 'search, line 60');
        await step(controller.next, 'next, line 120');
        await step(controller.next, 'next scrolls down to line 190');
        await step(controller.next, 'next scrolls up to line 60');
      });

      testWidgets('keeps 72 from both edges with no bar to measure', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = FindInPageController();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);

        // With showBar false the find UI belongs to the app, and the scope
        // cannot tell where it is.
        await tester.pumpWidget(
          _page(kind, controller: controller, scroll: scroll, showBar: false),
        );
        final body = tester.getRect(find.byType(SingleChildScrollView));

        Future<void> step(void Function() move, String name) async {
          final before = scroll.offset;
          move();
          await tester.pumpAndSettle();
          final rect = _activeRect(tester, controller);
          expect(scroll.offset, isNot(before), reason: name);
          final gap = scroll.offset < before
              ? rect.top - body.top
              : body.bottom - rect.bottom;
          expect(gap, closeTo(72, 0.5), reason: '$name: $rect');
        }

        await step(() => controller.search('needle'), 'search, line 60');
        await step(controller.next, 'next, line 120');
        await step(controller.next, 'next, line 190');
        await step(controller.next, 'next scrolls up to line 60');
      });

      testWidgets('keeps the margin for a match in a sideways row', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = FindInPageController();
        addTearDown(controller.dispose);

        const rowKey = ValueKey('row');
        await tester.pumpWidget(
          MaterialApp(
            home: FindInPageScope(
              controller: controller,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 1200),
                      // About the height of a row of chips. Its height must
                      // not cut the margin of the page around it.
                      SizedBox(
                        height: 48,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: kind.build(
                            'row needle',
                            key: rowKey,
                            softWrap: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1200),
                      kind.build('line needle', key: const ValueKey('line')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        controller.open();
        await tester.pumpAndSettle();
        final bar = tester.getRect(find.byType(FindBar));

        controller.search('needle');
        await tester.pumpAndSettle();
        controller.next();
        await tester.pumpAndSettle();
        // Wraps to the row, scrolling the page up.
        controller.next();
        await tester.pumpAndSettle();
        final match = controller.activeMatch!;
        expect(match.source.findableText, 'row needle');
        final rect = _matchRect(tester, rowKey, match);
        expect(rect.top - bar.bottom, closeTo(16, 0.5), reason: '$rect $bar');
        expect(rect.overlaps(bar), isFalse, reason: '$rect under the bar $bar');
      });

      testWidgets('leaves a match mid-viewport in place', (tester) async {
        final controller = FindInPageController();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);

        const needles = {70, 75};
        await tester.pumpWidget(
          MaterialApp(
            home: FindInPageScope(
              controller: controller,
              child: Scaffold(
                body: SingleChildScrollView(
                  controller: scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 1; i <= 200; i++)
                        kind.build(
                          needles.contains(i) ? 'line $i needle' : 'line $i',
                          key: ValueKey(i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        // Away from both ends of the scroll range, where clamping would hide
        // a reveal that moves the page.
        scroll.jumpTo(1100);
        await tester.pump();
        final body = tester.getRect(find.byType(SingleChildScrollView));
        final middle = tester.getRect(find.byKey(const ValueKey(70)));
        expect(middle.top, greaterThan(body.top + body.height / 3));
        expect(middle.bottom, lessThan(body.bottom - body.height / 3));

        controller.search('needle');
        await tester.pumpAndSettle();
        expect(scroll.offset, 1100, reason: 'line 70 was on screen');

        controller.next();
        await tester.pumpAndSettle();
        expect(scroll.offset, 1100, reason: 'line 75 was on screen');
      });

      for (final height in [300, 60]) {
        testWidgets('shows each match, $height px tall', (tester) async {
          final controller = FindInPageController();
          final scroll = ScrollController();
          addTearDown(controller.dispose);
          addTearDown(scroll.dispose);

          const viewportKey = ValueKey('viewport');
          const textKey = ValueKey('text');
          const needles = {3, 20, 21, 40, 58};
          final data = [
            for (var i = 1; i <= 60; i++)
              needles.contains(i) ? 'line $i needle' : 'line $i',
          ].join('\n');
          await tester.pumpWidget(
            MaterialApp(
              home: FindInPageScope(
                controller: controller,
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      key: viewportKey,
                      width: 300,
                      height: height.toDouble(),
                      child: SingleChildScrollView(
                        controller: scroll,
                        child: kind.build(data, key: textKey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final viewport = tester.getRect(find.byKey(viewportKey));

          Future<void> step(void Function() move, String name) async {
            move();
            await tester.pumpAndSettle();
            final rect = _matchRect(tester, textKey, controller.activeMatch!);
            expect(_inside(rect, viewport), isTrue, reason: '$name: $rect');
          }

          await step(() => controller.search('needle'), 'search');
          for (var i = 1; i <= 5; i++) {
            await step(controller.next, 'next $i');
          }
          for (var i = 1; i <= 5; i++) {
            await step(controller.previous, 'previous $i');
          }
        });
      }

      // A sideways scroll view inside a vertical one.
      testWidgets('reveals across nested scroll views', (tester) async {
        final controller = FindInPageController();
        final vertical = ScrollController();
        final horizontal = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(vertical.dispose);
        addTearDown(horizontal.dispose);

        const viewportKey = ValueKey('viewport');
        const textKey = ValueKey('wide');
        final pad = List.filled(150, 'x').join();
        final data = [
          for (var i = 1; i <= 80; i++) i == 60 ? '$pad needle $i' : 'line $i',
        ].join('\n');
        await tester.pumpWidget(
          MaterialApp(
            home: FindInPageScope(
              controller: controller,
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    key: viewportKey,
                    width: 400,
                    height: 300,
                    child: SingleChildScrollView(
                      controller: vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: horizontal,
                        child: kind.build(data, key: textKey, softWrap: false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        controller.search('needle');
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byKey(viewportKey));
        final rect = _matchRect(tester, textKey, controller.activeMatch!);
        expect(vertical.offset, greaterThan(0));
        expect(horizontal.offset, greaterThan(0));
        expect(_inside(rect, viewport), isTrue, reason: '$rect');
      });

      testWidgets('reveals inside a SelectionArea', (tester) async {
        final controller = FindInPageController();
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);

        const viewportKey = ValueKey('viewport');
        const textKey = ValueKey('tall');
        final data = [
          for (var i = 1; i <= 80; i++) i == 75 ? 'line $i needle' : 'line $i',
        ].join('\n');
        await tester.pumpWidget(
          MaterialApp(
            home: FindInPageScope(
              controller: controller,
              child: Scaffold(
                body: SizedBox(
                  key: viewportKey,
                  height: 220,
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: kind.build(data, key: textKey),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        controller.search('needle');
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byKey(viewportKey));
        final rect = _matchRect(tester, textKey, controller.activeMatch!);
        expect(_inside(rect, viewport), isTrue, reason: '$rect');
      });
    });
  }
}

/// A page of 200 lines with no app bar. Lines 60, 120 and 190 hold `needle`,
/// and the widget drawing line `i` has the key `ValueKey(i)`.
Widget _page(
  _Kind kind, {
  required FindInPageController controller,
  required ScrollController scroll,
  AlignmentGeometry barAlignment = AlignmentDirectional.topEnd,
  bool showBar = true,
}) {
  const needles = {60, 120, 190};
  return MaterialApp(
    home: FindInPageScope(
      controller: controller,
      barAlignment: barAlignment,
      showBar: showBar,
      child: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 1; i <= 200; i++)
                kind.build(
                  needles.contains(i) ? 'line $i needle' : 'line $i',
                  key: ValueKey(i),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The active match of a [_page] in global coordinates.
Rect _activeRect(WidgetTester tester, FindInPageController controller) {
  final match = controller.activeMatch!;
  final line = int.parse(match.source.findableText.split(' ')[1]);
  return _matchRect(tester, ValueKey(line), match);
}

enum _Kind {
  findableText,
  discoveredText;

  Widget build(String data, {required Key key, bool softWrap = true}) =>
      switch (this) {
        _Kind.findableText => FindableText(data, key: key, softWrap: softWrap),
        _Kind.discoveredText => Text(data, key: key, softWrap: softWrap),
      };
}

/// The first box of [match] in global coordinates. [key] marks the widget
/// that draws the paragraph holding it.
Rect _matchRect(WidgetTester tester, Key key, FindMatch match) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
  );
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      )
      .first
      .toRect();
  return MatrixUtils.transformRect(paragraph.getTransformTo(null), box);
}

bool _inside(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.bottom <= outer.bottom + 0.5;
